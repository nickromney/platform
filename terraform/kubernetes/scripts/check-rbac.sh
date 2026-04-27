#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage: check-rbac.sh

Checks the stage-900 demo RBAC model with kubectl auth can-i.

By default this runs impersonation checks and, when the stage-900 Keycloak
resources are present, real OIDC token checks. Set
PLATFORM_RBAC_REAL_TOKEN_CHECK=off to skip the real-token checks.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  fail "Unknown argument: $1"
done

shell_cli_maybe_execute_or_preview_summary usage "would check platform RBAC with kubectl auth can-i"

command -v kubectl >/dev/null 2>&1 || fail "kubectl not found in PATH"
command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
command -v curl >/dev/null 2>&1 || fail "curl not found in PATH"
kubectl get namespaces >/dev/null

ADMIN_USER="${PLATFORM_RBAC_ADMIN_USER:-demo@admin.test}"
VIEWER_USER="${PLATFORM_RBAC_VIEWER_USER:-demo@dev.test}"
ADMIN_GROUP="${PLATFORM_RBAC_ADMIN_GROUP:-platform-admins}"
VIEWER_GROUP="${PLATFORM_RBAC_VIEWER_GROUP:-platform-viewers}"
KEYCLOAK_NAMESPACE="${PLATFORM_RBAC_KEYCLOAK_NAMESPACE:-sso}"
KEYCLOAK_REALM="${PLATFORM_RBAC_KEYCLOAK_REALM:-platform}"
KEYCLOAK_ADMIN_SECRET="${PLATFORM_RBAC_KEYCLOAK_ADMIN_SECRET:-keycloak-admin}"
KUBERNETES_OIDC_CLIENT_ID="${PLATFORM_RBAC_KUBERNETES_OIDC_CLIENT_ID:-headlamp}"
KEYCLOAK_TOKEN_URL="${PLATFORM_RBAC_KEYCLOAK_TOKEN_URL:-https://keycloak.127.0.0.1.sslip.io/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token}"
REAL_TOKEN_CHECK="${PLATFORM_RBAC_REAL_TOKEN_CHECK:-auto}"
REAL_AUTH_TMPDIR=""
REAL_KUBECTL_ARGS=()

can_i() {
  local expected="$1"
  shift
  local output
  output="$(kubectl auth can-i "$@" 2>/dev/null || true)"
  if [[ "${output}" == "${expected}" ]]; then
    ok "kubectl auth can-i $* -> ${expected}"
    return 0
  fi
  fail "kubectl auth can-i $* -> ${output:-<empty>}; expected ${expected}"
}

can_i yes '*' '*' --as="${ADMIN_USER}" --as-group="${ADMIN_GROUP}"
can_i yes get pods -n dev --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
can_i yes list deployments.apps -n uat --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
can_i no delete pods -n dev --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"
can_i no create deployments.apps -n uat --as="${VIEWER_USER}" --as-group="${VIEWER_GROUP}"

decode_b64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

cleanup_real_auth_tmpdir() {
  [[ -z "${REAL_AUTH_TMPDIR}" ]] || rm -rf "${REAL_AUTH_TMPDIR}"
}

prepare_real_token_kubectl_args() {
  local server ca_data ca_file

  [[ "${#REAL_KUBECTL_ARGS[@]}" -eq 0 ]] || return 0

  server="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
  ca_data="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || true)"
  [[ -n "${server}" && -n "${ca_data}" ]] || fail "current kubeconfig must expose server and certificate-authority-data for real-token RBAC checks"

  REAL_AUTH_TMPDIR="$(mktemp -d)"
  trap cleanup_real_auth_tmpdir EXIT
  ca_file="${REAL_AUTH_TMPDIR}/ca.crt"
  printf '%s' "${ca_data}" | decode_b64 >"${ca_file}"
  REAL_KUBECTL_ARGS=(--server="${server}" --certificate-authority="${ca_file}")
}

secret_field() {
  local secret_name="$1"
  local field_name="$2"

  kubectl -n "${KEYCLOAK_NAMESPACE}" get secret "${secret_name}" -o "jsonpath={.data.${field_name}}" 2>/dev/null |
    decode_b64 || true
}

keycloak_pod_name() {
  kubectl -n "${KEYCLOAK_NAMESPACE}" get pod -l app.kubernetes.io/name=keycloak \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

kcadm() {
  local pod="$1"
  shift
  kubectl -n "${KEYCLOAK_NAMESPACE}" exec "${pod}" -- /opt/keycloak/bin/kcadm.sh "$@"
}

keycloak_client_secret() {
  local pod="$1"
  local admin_user="$2"
  local admin_password="$3"
  local client_id="$4"
  local client_uuid

  kcadm "${pod}" config credentials \
    --server http://127.0.0.1:8080 \
    --realm master \
    --user "${admin_user}" \
    --password "${admin_password}" >/dev/null

  client_uuid="$(
    kcadm "${pod}" get clients -r "${KEYCLOAK_REALM}" -q "clientId=${client_id}" --fields id,clientId |
      jq -r --arg clientId "${client_id}" '.[] | select(.clientId == $clientId) | .id' |
      head -n 1
  )"
  [[ -n "${client_uuid}" ]] || fail "Keycloak client not found for real-token RBAC check: ${client_id}"

  kcadm "${pod}" get "clients/${client_uuid}/client-secret" -r "${KEYCLOAK_REALM}" |
    jq -r '.value // empty'
}

keycloak_id_token() {
  local username="$1"
  local password="$2"
  local client_id="$3"
  local client_secret="$4"
  local response token

  response="$(
    curl -ksS \
      -X POST "${KEYCLOAK_TOKEN_URL}" \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "grant_type=password" \
      --data-urlencode "client_id=${client_id}" \
      --data-urlencode "client_secret=${client_secret}" \
      --data-urlencode "username=${username}" \
      --data-urlencode "password=${password}" \
      --data-urlencode "scope=openid profile email groups"
  )"
  token="$(jq -r '.id_token // empty' <<<"${response}")"
  [[ -n "${token}" ]] || fail "Keycloak did not return an id_token for ${username}: ${response}"
  printf '%s' "${token}"
}

real_can_i() {
  local expected="$1"
  local token="$2"
  shift 2
  local output
  prepare_real_token_kubectl_args
  output="$(KUBECONFIG=/dev/null kubectl "${REAL_KUBECTL_ARGS[@]}" --token="${token}" auth can-i "$@" 2>/dev/null || true)"
  if [[ "${output}" == "${expected}" ]]; then
    ok "real OIDC token kubectl auth can-i $* -> ${expected}"
    return 0
  fi
  fail "real OIDC token kubectl auth can-i $* -> ${output:-<empty>}; expected ${expected}"
}

run_real_token_checks() {
  local pod admin_user admin_password client_secret admin_token viewer_token

  if [[ "${REAL_TOKEN_CHECK}" == "off" ]]; then
    ok "real OIDC token RBAC checks skipped by PLATFORM_RBAC_REAL_TOKEN_CHECK=off"
    return 0
  fi

  pod="$(keycloak_pod_name)"
  if [[ -z "${pod}" ]]; then
    if [[ "${REAL_TOKEN_CHECK}" == "on" ]]; then
      fail "Keycloak pod not found for real-token RBAC check"
    fi
    ok "real OIDC token RBAC checks skipped because Keycloak is not present"
    return 0
  fi

  admin_user="$(secret_field "${KEYCLOAK_ADMIN_SECRET}" username)"
  admin_password="$(secret_field "${KEYCLOAK_ADMIN_SECRET}" password)"
  [[ -n "${admin_user}" && -n "${admin_password}" ]] || fail "Keycloak admin secret missing username/password: ${KEYCLOAK_ADMIN_SECRET}"

  client_secret="$(keycloak_client_secret "${pod}" "${admin_user}" "${admin_password}" "${KUBERNETES_OIDC_CLIENT_ID}")"
  [[ -n "${client_secret}" ]] || fail "Keycloak client secret missing for ${KUBERNETES_OIDC_CLIENT_ID}"

  admin_token="$(keycloak_id_token "${ADMIN_USER}" "${admin_password}" "${KUBERNETES_OIDC_CLIENT_ID}" "${client_secret}")"
  viewer_token="$(keycloak_id_token "${VIEWER_USER}" "${admin_password}" "${KUBERNETES_OIDC_CLIENT_ID}" "${client_secret}")"

  real_can_i yes "${admin_token}" '*' '*'
  real_can_i yes "${viewer_token}" get pods -n dev
  real_can_i yes "${viewer_token}" list deployments.apps -n uat
  real_can_i no "${viewer_token}" delete pods -n dev
  real_can_i no "${viewer_token}" create deployments.apps -n uat
}

run_real_token_checks
