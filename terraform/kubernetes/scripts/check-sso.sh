#!/usr/bin/env bash
set -euo pipefail

FAILURES=0

fail() { echo "FAIL $*" >&2; exit 1; }
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage: check-sso.sh [--var-file PATH] [--host-port PORT] [--extended]

Checks the Dex + oauth2-proxy SSO plumbing with an emphasis on Gitea.
This is a read-only diagnostic script.
EOF
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
while [[ $# -gt 0 ]]; do
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

for i in "${!TFVARS_FILES[@]}"; do
  if [[ -n "${TFVARS_FILES[i]}" && ! -f "${TFVARS_FILES[i]}" && -f "${STACK_DIR}/${TFVARS_FILES[i]}" ]]; then
    TFVARS_FILES[i]="${STACK_DIR}/${TFVARS_FILES[i]}"
  fi
done

tfvar_get() {
  local key="$2"
  local file value=""
  for file in "${TFVARS_FILES[@]}"; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    value="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true)"
    [[ -n "${value}" ]] || continue
  done
  echo "${value}"
}

admin_host() {
  local app="$1"
  if [[ "${SEPARATE_ADMIN_DOMAIN}" == "1" ]]; then
    printf '%s.%s\n' "${app}" "${PLATFORM_ADMIN_BASE_DOMAIN}"
  else
    printf '%s.admin.%s\n' "${app}" "${PLATFORM_BASE_DOMAIN}"
  fi
}

dex_host() {
  printf 'dex.%s\n' "${PLATFORM_ADMIN_BASE_DOMAIN}"
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
EXPECTED_DEX_ISSUER_URL="https://$(dex_host)${port_suffix}/dex"

EXPECTED_CLUSTER_NAME="$(tfvar_get "" cluster_name)"
EXPECT_KIND_PROVISIONING="$(tfvar_get "" provision_kind_cluster)"
if [[ -z "${EXPECTED_CLUSTER_NAME}" ]]; then
  EXPECTED_CLUSTER_NAME="${KUBECONFIG_CONTEXT:-}"
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
  for app in dex oauth2-proxy-gitea; do
    if kubectl -n argocd get app "${app}" >/dev/null 2>&1; then
      sync=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
      health=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
      if [[ "${health}" == "Healthy" && "${sync}" == "Synced" ]]; then
        ok "app ${app} Synced/Healthy"
      else
        warn "app ${app} sync=${sync:-?} health=${health:-?}"
      fi
    else
      warn "app ${app} missing"
    fi
  done
else
  warn "Argo CD apps not queryable in ns=argocd"
fi

echo ""
echo "Dex (in-cluster):"
if kubectl -n sso get deploy dex >/dev/null 2>&1; then
  ok "deploy sso/dex present"
else
  fail_soft "deploy sso/dex missing"
fi

echo ""
echo "oauth2-proxy for Gitea (in-cluster):"
if kubectl -n sso get deploy oauth2-proxy-gitea >/dev/null 2>&1; then
  ok "deploy sso/oauth2-proxy-gitea present"
  expect_deploy_arg sso oauth2-proxy-gitea "--provider=oidc"
  expect_deploy_arg sso oauth2-proxy-gitea "--scope=openid email profile"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-issuer-url=${EXPECTED_DEX_ISSUER_URL}"
  expect_deploy_arg sso oauth2-proxy-gitea "--profile-url=http://dex.sso.svc.cluster.local:5556/dex/userinfo"
  expect_deploy_arg sso oauth2-proxy-gitea "--redeem-url=http://dex.sso.svc.cluster.local:5556/dex/token"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-jwks-url=http://dex.sso.svc.cluster.local:5556/dex/keys"
  expect_deploy_arg sso oauth2-proxy-gitea "--skip-oidc-discovery=true"
  expect_deploy_arg sso oauth2-proxy-gitea "--oidc-email-claim=email"
  expect_deploy_arg sso oauth2-proxy-gitea "--user-id-claim=email"
  expect_deploy_arg sso oauth2-proxy-gitea "--pass-user-headers=true"
else
  fail_soft "deploy sso/oauth2-proxy-gitea missing"
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

  print_http_head "https://$(dex_host)${port_suffix}/dex/.well-known/openid-configuration" 5
  print_http_head "https://$(dex_host)${port_suffix}/dex/keys" 5
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
