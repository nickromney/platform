#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

FAILURES=0

fail() { echo "FAIL $*" >&2; exit 1; }
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage: check-sso.sh [--var-file PATH] [--host-port PORT] [--extended]

Checks the selected OIDC provider + oauth2-proxy SSO plumbing with an emphasis on Gitea.
This is a read-only diagnostic script.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

TFVARS_FILES=()
HOST_PORT=""
EXTENDED="${EXTENDED:-0}"
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --var-file)
      TFVARS_FILES+=("${2:-}")
      shift 2
      ;;
    --host-port)
      HOST_PORT="${2:-}"
      shift 2
      ;;
    -x|--extended|--debug)
      EXTENDED=1
      shift
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would check the OIDC provider and oauth2-proxy SSO plumbing"

for i in "${!TFVARS_FILES[@]}"; do
  if [[ -n "${TFVARS_FILES[i]}" && ! -f "${TFVARS_FILES[i]}" && -f "${STACK_DIR}/${TFVARS_FILES[i]}" ]]; then
    TFVARS_FILES[i]="${STACK_DIR}/${TFVARS_FILES[i]}"
  fi
done

tfvar_get() {
  local key="$2"
  local file value=""
  local i=0
  for (( i=${#TFVARS_FILES[@]}-1; i>=0; i-- )); do
    file="${TFVARS_FILES[$i]}"
    [[ -n "${file}" && -f "${file}" ]] || continue
    value="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true)"
    [[ -n "${value}" ]] || continue
    echo "${value}"
    return 0
  done
  echo ""
}

admin_host() {
  local app="$1"
  if [[ "${SEPARATE_ADMIN_DOMAIN}" == "1" ]]; then
    printf '%s.%s\n' "${app}" "${PLATFORM_ADMIN_BASE_DOMAIN}"
  else
    printf '%s.admin.%s\n' "${app}" "${PLATFORM_BASE_DOMAIN}"
  fi
}

oidc_host() {
  if [[ "${SSO_PROVIDER}" == "keycloak" ]]; then
    printf 'keycloak.%s\n' "${PLATFORM_ADMIN_BASE_DOMAIN}"
  else
    printf 'dex.%s\n' "${PLATFORM_ADMIN_BASE_DOMAIN}"
  fi
}

expect_deploy_arg() {
  local ns="$1"
  local deploy="$2"
  local prefix="$3"

  local args
  # Note: kubectl's jsonpath requires {@} (not {.}) to print primitive array elements.
  args=$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${args}" ]]; then
    fail_soft "${ns}/${deploy} args not found (unexpected chart layout?)"
    return 0
  fi

  if echo "${args}" | grep -Fqx -- "${prefix}"; then
    ok "${ns}/${deploy} has arg: ${prefix}"
    return 0
  fi
  if echo "${args}" | grep -Fq -- "${prefix}"; then
    ok "${ns}/${deploy} has arg: ${prefix}"
    return 0
  fi
  fail_soft "${ns}/${deploy} missing arg: ${prefix}"
}

warn_if_deploy_arg_present() {
  local ns="$1"
  local deploy="$2"
  local needle="$3"
  local msg="$4"

  local args
  args=$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${args}" ]]; then
    return 0
  fi
  if echo "${args}" | grep -Fq -- "${needle}"; then
    warn "${msg}"
  fi
}

print_http_head() {
  local url="$1"
  local max_time="${2:-5}"

  local out code
  out=$(curl -k -sS -I --max-time "${max_time}" "${url}" 2>/dev/null || true)
  code=$(echo "${out}" | awk 'BEGIN{c=""} tolower($1)=="http/1.1"||tolower($1)=="http/2"{c=$2} END{print c}')

  if [[ -z "${out}" ]]; then
    warn "HTTPS ${url} -> error"
    return 0
  fi

  if [[ "${code}" =~ ^2|^3|^4 ]]; then
    echo "${out}" | sed -n '1p;/^[Ll]ocation:/p' | sed 's/\r$//' | while IFS= read -r line; do
      [[ -n "${line}" ]] && echo "  ${line}"
    done
    if [[ "${code}" =~ ^2|^3 ]]; then
      ok "HTTPS ${url} -> ${code}"
    else
      warn "HTTPS ${url} -> ${code}"
    fi
  else
    warn "HTTPS ${url} -> ${code:-unknown}"
  fi
}

require_cmd kubectl
require_cmd jq

if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT=$(tfvar_get "" gateway_https_host_port)
fi
if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT="443"
fi

PLATFORM_BASE_DOMAIN=$(tfvar_get "" platform_base_domain)
if [[ -z "${PLATFORM_BASE_DOMAIN}" ]]; then
  PLATFORM_BASE_DOMAIN="127.0.0.1.sslip.io"
fi
PLATFORM_ADMIN_BASE_DOMAIN=$(tfvar_get "" platform_admin_base_domain)
SEPARATE_ADMIN_DOMAIN=0
if [[ -n "${PLATFORM_ADMIN_BASE_DOMAIN}" ]]; then
  SEPARATE_ADMIN_DOMAIN=1
else
  PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN}"
fi

port_suffix=""
if [[ "${HOST_PORT}" != "443" ]]; then
  port_suffix=":${HOST_PORT}"
fi
SSO_PROVIDER="$(tfvar_get "" sso_provider)"
[[ -n "${SSO_PROVIDER}" ]] || SSO_PROVIDER="keycloak"
KEYCLOAK_REALM="$(tfvar_get "" keycloak_realm)"
[[ -n "${KEYCLOAK_REALM}" ]] || KEYCLOAK_REALM="platform"
EXPECTED_APIM_AUDIENCE="${PLATFORM_APIM_OIDC_AUDIENCE:-apim-simulator}"
if [[ "${SSO_PROVIDER}" == "keycloak" ]]; then
  OIDC_DEPLOYMENT="keycloak"
  EXPECTED_OIDC_ISSUER_URL="https://$(oidc_host)${port_suffix}/realms/${KEYCLOAK_REALM}"
  EXPECTED_PROFILE_URL="http://keycloak.sso.svc.cluster.local:8080/realms/${KEYCLOAK_REALM}/protocol/openid-connect/userinfo"
  EXPECTED_TOKEN_URL="http://keycloak.sso.svc.cluster.local:8080/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token"
  EXPECTED_JWKS_URL="http://keycloak.sso.svc.cluster.local:8080/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs"
else
  OIDC_DEPLOYMENT="dex"
  EXPECTED_OIDC_ISSUER_URL="https://$(oidc_host)${port_suffix}/dex"
  EXPECTED_PROFILE_URL="http://dex.sso.svc.cluster.local:5556/dex/userinfo"
  EXPECTED_TOKEN_URL="http://dex.sso.svc.cluster.local:5556/dex/token"
  EXPECTED_JWKS_URL="http://dex.sso.svc.cluster.local:5556/dex/keys"
fi

EXPECTED_CLUSTER_NAME="$(tfvar_get "" cluster_name)"
EXPECT_KIND_PROVISIONING="$(tfvar_get "" provision_kind_cluster)"
if [[ -z "${EXPECTED_CLUSTER_NAME}" ]]; then
  EXPECTED_CLUSTER_NAME="${TARGET_CLUSTER_NAME:-${CLUSTER_NAME:-}}"
fi
if [[ -z "${EXPECTED_CLUSTER_NAME}" ]]; then
  if [[ "${KUBECONFIG_CONTEXT:-}" == kind-* ]]; then
    EXPECTED_CLUSTER_NAME="${KUBECONFIG_CONTEXT#kind-}"
  else
    EXPECTED_CLUSTER_NAME="${KUBECONFIG_CONTEXT:-}"
  fi
fi
if [[ -z "${EXPECTED_CLUSTER_NAME}" ]]; then
  EXPECTED_CLUSTER_NAME="$(kubectl config current-context 2>/dev/null || true)"
fi
[ -n "${EXPECTED_CLUSTER_NAME}" ] || EXPECTED_CLUSTER_NAME="kind-local"
[ -n "${EXPECT_KIND_PROVISIONING}" ] || EXPECT_KIND_PROVISIONING="true"

if [[ "${EXPECT_KIND_PROVISIONING}" == "true" ]]; then
  require_cmd kind
  echo "Checking kind cluster..."
  if ! kind get clusters 2>/dev/null | grep -qx "${EXPECTED_CLUSTER_NAME}"; then
    fail "${EXPECTED_CLUSTER_NAME} cluster not found"
  fi
  ok "${EXPECTED_CLUSTER_NAME} cluster exists"
else
  echo "Checking Kubernetes cluster..."
  ok "Using existing kubeconfig-backed cluster (${EXPECTED_CLUSTER_NAME})"
fi

kubectl get nodes >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
ok "kubectl can reach the cluster"

echo ""
echo "Namespaces:"
for ns in argocd sso gitea headlamp platform-gateway gateway-routes; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    ok "namespace ${ns} present"
  else
    warn "namespace ${ns} missing"
  fi
done

echo ""
echo "Argo CD apps (if present):"
if kubectl -n argocd get applications.argoproj.io >/dev/null 2>&1; then
  for app in "${OIDC_DEPLOYMENT}" oauth2-proxy-gitea; do
    if kubectl -n argocd get app "${app}" >/dev/null 2>&1; then
      sync=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
      health=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
      if [[ "${health}" == "Healthy" && "${sync}" == "Synced" ]]; then
        ok "app ${app} Synced/Healthy"
      else
        warn "app ${app} sync=${sync:-?} health=${health:-?}"
      fi
    elif [[ "${app}" == "${OIDC_DEPLOYMENT}" && "${SSO_PROVIDER}" == "keycloak" ]] &&
      kubectl -n sso get deploy keycloak >/dev/null 2>&1; then
      ok "app keycloak not required; Keycloak is managed directly in the sso namespace"
    else
      warn "app ${app} missing"
    fi
  done
else
  warn "Argo CD apps not queryable in ns=argocd"
fi

echo ""
echo "OIDC provider (in-cluster):"
if kubectl -n sso get deploy "${OIDC_DEPLOYMENT}" >/dev/null 2>&1; then
  ok "deploy sso/${OIDC_DEPLOYMENT} present"
else
  fail_soft "deploy sso/${OIDC_DEPLOYMENT} missing"
fi

echo ""
echo "oauth2-proxy for Gitea (in-cluster):"
if kubectl -n sso get deploy oauth2-proxy-gitea >/dev/null 2>&1; then
  ok "deploy sso/oauth2-proxy-gitea present"
  expect_deploy_arg sso oauth2-proxy-gitea "--provider=oidc"
  expect_deploy_arg sso oauth2-proxy-gitea "--scope=openid email profile groups"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-issuer-url=${EXPECTED_OIDC_ISSUER_URL}"
  expect_deploy_arg sso oauth2-proxy-gitea "--profile-url=${EXPECTED_PROFILE_URL}"
  expect_deploy_arg sso oauth2-proxy-gitea "--redeem-url=${EXPECTED_TOKEN_URL}"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-jwks-url=${EXPECTED_JWKS_URL}"
  expect_deploy_arg sso oauth2-proxy-gitea "--skip-oidc-discovery=true"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-email-claim=email"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-groups-claim=groups"
  expect_deploy_arg sso oauth2-proxy-gitea "--allowed-group=platform-admins"
  expect_deploy_arg sso oauth2-proxy-gitea "--user-id-claim=email"
  expect_deploy_arg sso oauth2-proxy-gitea "--pass-user-headers=true"
  warn_if_deploy_arg_present sso oauth2-proxy-gitea "--email-domain=admin.test" "oauth2-proxy-gitea still uses email-domain instead of group RBAC"
else
  fail_soft "deploy sso/oauth2-proxy-gitea missing"
fi

echo ""
echo "APIM OIDC resource-server config (in-cluster):"
if kubectl -n apim get configmap subnetcalc-apim-simulator-config >/dev/null 2>&1; then
  apim_config_json="$(kubectl -n apim get configmap subnetcalc-apim-simulator-config -o json)"
  apim_issuer="$(jq -r '.data["config.json"] | fromjson | .oidc.issuer // ""' <<<"${apim_config_json}")"
  apim_audience="$(jq -r '.data["config.json"] | fromjson | .oidc.audience // ""' <<<"${apim_config_json}")"
  apim_jwks_uri="$(jq -r '.data["config.json"] | fromjson | .oidc.jwks_uri // ""' <<<"${apim_config_json}")"

  if [[ "${apim_issuer}" == "${EXPECTED_OIDC_ISSUER_URL}" ]]; then
    ok "APIM validates issuer ${apim_issuer}"
  else
    fail_soft "APIM issuer ${apim_issuer:-<empty>} does not match ${EXPECTED_OIDC_ISSUER_URL}"
  fi

  if [[ "${apim_audience}" == "${EXPECTED_APIM_AUDIENCE}" ]]; then
    ok "APIM validates dedicated audience ${apim_audience}"
  else
    fail_soft "APIM audience ${apim_audience:-<empty>} does not match ${EXPECTED_APIM_AUDIENCE}"
  fi

  if [[ "${apim_jwks_uri}" == "${EXPECTED_JWKS_URL}" ]]; then
    ok "APIM validates JWKS ${apim_jwks_uri}"
  else
    fail_soft "APIM JWKS ${apim_jwks_uri:-<empty>} does not match ${EXPECTED_JWKS_URL}"
  fi
else
  warn "configmap apim/subnetcalc-apim-simulator-config missing"
fi

echo ""
echo "Gitea reverse-proxy auth config (in-cluster):"
if kubectl -n gitea get deploy gitea >/dev/null 2>&1; then
  ok "deploy gitea/gitea present"

  cfg_path="/data/gitea/conf/app.ini"
  if kubectl -n gitea exec deploy/gitea -c gitea -- sh -c "test -f '${cfg_path}'" >/dev/null 2>&1; then
    lines=$(kubectl -n gitea exec deploy/gitea -c gitea -- sh -c \
      "grep -inE '^(ENABLE_REVERSE_PROXY_AUTHENTICATION|ENABLE_REVERSE_PROXY_AUTO_REGISTRATION|REVERSE_PROXY_AUTHENTICATION_(USER|EMAIL|FULL_NAME)|ENABLE_REVERSE_PROXY_(EMAIL|FULL_NAME))[[:space:]]*=' '${cfg_path}' || true" \
      2>/dev/null || true)
    if [[ -n "${lines}" ]]; then
      printf '  %s\n' "${lines//$'\n'/$'\n  '}"
      ok "reverse-proxy auth keys found in app.ini"
    else
      warn "reverse-proxy auth keys not found in ${cfg_path}"
    fi
  else
    warn "gitea config not found at ${cfg_path}"
  fi
else
  warn "deploy gitea/gitea missing"
fi

if have_cmd curl; then
  echo ""
  echo "External HTTPS checks (host port ${HOST_PORT}):"

  print_http_head "${EXPECTED_OIDC_ISSUER_URL}/.well-known/openid-configuration" 5
  print_http_head "https://$(admin_host gitea)${port_suffix}/" 5
  print_http_head "https://$(admin_host headlamp)${port_suffix}/" 5

  if [[ "${EXTENDED}" -eq 1 ]]; then
    echo ""
    echo "Logs (last 80 lines):"
    kubectl -n sso logs deploy/oauth2-proxy-gitea --tail=80 2>/dev/null || true
    echo ""
    kubectl -n gitea logs deploy/gitea -c gitea --tail=80 2>/dev/null || true
  fi
else
  warn "curl not found; skipping external HTTPS checks"
fi

echo ""
if [[ "${FAILURES}" -gt 0 ]]; then
  fail "${FAILURES} check(s) failed"
fi

ok "SSO check completed"
