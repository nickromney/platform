#!/usr/bin/env bash
set -euo pipefail

fail() { echo "fetch-gitea-runner-token: $*" >&2; exit 1; }
log() { echo "fetch-gitea-runner-token: $*" >&2; }

command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v jq >/dev/null 2>&1 || fail "jq not found"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="$(cat)"
GITEA_HTTP_BASE="$(jq -r '.gitea_http_base // empty' <<<"${query}")"
GITEA_ADMIN_USERNAME="$(jq -r '.gitea_admin_username // empty' <<<"${query}")"
GITEA_ADMIN_PWD="$(jq -r '.gitea_admin_pwd // empty' <<<"${query}")"
GITEA_LOCAL_ACCESS_MODE="$(jq -r '.gitea_local_access_mode // empty' <<<"${query}")"
GITEA_HTTP_NODE_PORT="$(jq -r '.gitea_http_node_port // empty' <<<"${query}")"
GITEA_SSH_NODE_PORT="$(jq -r '.gitea_ssh_node_port // empty' <<<"${query}")"
export GITEA_LOCAL_ACCESS_MODE GITEA_HTTP_NODE_PORT GITEA_SSH_NODE_PORT
GITEA_NAMESPACE="$(jq -r '.gitea_namespace // empty' <<<"${query}")"
KUBECONFIG_PATH="$(jq -r '.kubeconfig_path // empty' <<<"${query}")"
KUBECONFIG_CONTEXT="$(jq -r '.kubeconfig_context // empty' <<<"${query}")"

if [[ -n "${KUBECONFIG_PATH}" ]]; then
  export KUBECONFIG="${KUBECONFIG_PATH}"
fi

KUBECTL_ARGS=()
if [[ -n "${KUBECONFIG_CONTEXT}" ]]; then
  KUBECTL_ARGS+=(--context "${KUBECONFIG_CONTEXT}")
fi

[[ -n "${GITEA_ADMIN_USERNAME}" ]] || fail "gitea_admin_username is required"
[[ -n "${GITEA_ADMIN_PWD}" ]] || fail "gitea_admin_pwd is required"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/gitea-local-access.sh"
trap 'gitea_local_access_cleanup || true' EXIT
gitea_local_access_setup http
: "${GITEA_HTTP_BASE:?gitea_http_base is required after local access setup}"

request_runner_token() {
  local body_file http_code
  body_file="$(mktemp)"
  http_code="$(
    curl -sS -o "$body_file" -w "%{http_code}" --connect-timeout 2 --max-time 10 \
      -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
      -X POST "${GITEA_HTTP_BASE}/api/v1/admin/actions/runners/registration-token"
  )"

  printf '%s\n' "$http_code"
  cat "$body_file"
  rm -f "$body_file"
}

unset_must_change_password() {
  local namespace="${GITEA_NAMESPACE:-gitea}"
  local deployment="${GITEA_DEPLOYMENT:-gitea}"
  local container="${GITEA_CONTAINER:-gitea}"

  command -v kubectl >/dev/null 2>&1 || fail "kubectl not found for must-change-password recovery"

  for _ in $(seq 1 60); do
    if kubectl "${KUBECTL_ARGS[@]}" -n "${namespace}" exec "deploy/${deployment}" -c "${container}" -- \
      gitea admin user must-change-password --all --unset >/dev/null 2>&1; then
      log "unset must-change-password for Gitea users"
      return 0
    fi
    sleep 2
  done

  fail "timed out unsetting Gitea must-change-password"
}

read_existing_runner_token() {
  local namespace="${GITEA_RUNNER_NAMESPACE:-gitea-runner}"
  local secret_name="${GITEA_RUNNER_SECRET_NAME:-act-runner-secret}"
  local secret_key="${GITEA_RUNNER_SECRET_KEY:-runner_token}"
  local token_b64 token

  command -v kubectl >/dev/null 2>&1 || return 1
  token_b64="$(
    kubectl "${KUBECTL_ARGS[@]}" -n "${namespace}" get secret "${secret_name}" \
      -o "jsonpath={.data.${secret_key}}" 2>/dev/null || true
  )"

  [[ -n "${token_b64}" ]] || return 1

  token="$(printf '%s' "${token_b64}" | base64 -d 2>/dev/null | tr -d '\r\n')"
  [[ -n "${token}" ]] || return 1

  printf '%s\n' "${token}"
}

if existing_token="$(read_existing_runner_token)"; then
  log "reusing existing in-cluster runner token"
  jq -cn --arg token "${existing_token}" '{token: $token}'
  exit 0
fi

for _ in {1..60}; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 \
    "${GITEA_HTTP_BASE}/api/v1/version" 2>/dev/null || echo 000)"
  if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
    break
  fi
  sleep 2
done

token_response="$(request_runner_token)"
token_http_code="$(printf '%s\n' "${token_response}" | sed -n '1p')"
token_body="$(printf '%s\n' "${token_response}" | sed '1d')"

if [[ "${token_http_code}" == "403" ]] && grep -q "must change your password" <<<"${token_body}"; then
  unset_must_change_password
  token_response="$(request_runner_token)"
  token_http_code="$(printf '%s\n' "${token_response}" | sed -n '1p')"
  token_body="$(printf '%s\n' "${token_response}" | sed '1d')"
fi

if [[ ! "${token_http_code}" =~ ^2[0-9][0-9]$ ]]; then
  fail "runner token request failed with HTTP ${token_http_code}: ${token_body}"
fi

token="$(jq -r '.token // empty' <<<"${token_body}" | tr -d '\r\n')"

[[ -n "${token}" ]] || fail "failed to obtain runner registration token"

jq -cn --arg token "${token}" '{token: $token}'
