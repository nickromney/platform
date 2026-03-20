#!/usr/bin/env bash
set -euo pipefail

FAILURES=0

fail() { echo "FAIL $*" >&2; exit 1; }
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage:
  check-app.sh --app NAME [options]

Purpose:
  Quick, repeatable diagnostics for an app exposed via the gateway (optionally behind oauth2-proxy),
  without relying on local DNS. Designed for the platform learning stack.

Required:
  --app NAME                     Base app name (e.g., signoz, gitea, argocd, hubble, headlamp)

Common options:
  --host HOST                    FQDN to probe (default: "${app}${host_suffix}")
  --host-suffix SUFFIX           Default: ".admin.127.0.0.1.sslip.io"
  --path PATH                    Default: "/"
  --host-port PORT               Default: from tfvars gateway_https_host_port, else 443
  --resolve-ip IP                Default: 127.0.0.1 (curl --resolve target)
  --since DURATION               Default: 20m (logs)
  --tail N                       Default: 200 (logs)
  -x, --extended                 Print more kubectl objects (pods/services/endpointslices/httproute yaml)
  --strict                       Exit non-zero on any failures (default)
  --no-strict                    Always exit 0 (for ad-hoc debugging)

Stack integration:
  --var-file PATH                Optional .tfvars; used for gateway host port + argocd namespace overrides.

Naming convention overrides:
  --argocd-ns NS                 Default: from tfvars argocd_namespace, else "argocd"
  --httproute-ns NS              Default: "gateway-routes"
  --httproute NAME               Default: "${app}"
  --sso-ns NS                    Default: "sso"
  --oauth2-proxy NAME            Default: "oauth2-proxy-${app}"

Examples:
  check-app.sh --app signoz --path /metrics-explorer/summary -x
  check-app.sh --app gitea --path / -x
  check-app.sh --app headlamp --host headlamp.admin.127.0.0.1.sslip.io --path /
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }
require() { have "$1" || fail "$1 not found in PATH"; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

TFVARS_FILE=""
APP=""
HOST=""
HOST_SUFFIX=".admin.127.0.0.1.sslip.io"
PATH_TO_CHECK="/"
HOST_PORT=""
RESOLVE_IP="127.0.0.1"
SINCE="20m"
TAIL="200"
EXTENDED=0
STRICT=1

ARGOCD_NS=""
HTTPROUTE_NS="gateway-routes"
HTTPROUTE_NAME=""
SSO_NS="sso"
OAUTH2_PROXY_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file) TFVARS_FILE="${2:-}"; shift 2 ;;
    --app) APP="${2:-}"; shift 2 ;;
    --host) HOST="${2:-}"; shift 2 ;;
    --host-suffix) HOST_SUFFIX="${2:-}"; shift 2 ;;
    --path) PATH_TO_CHECK="${2:-}"; shift 2 ;;
    --host-port) HOST_PORT="${2:-}"; shift 2 ;;
    --resolve-ip) RESOLVE_IP="${2:-}"; shift 2 ;;
    --since) SINCE="${2:-}"; shift 2 ;;
    --tail) TAIL="${2:-}"; shift 2 ;;
    -x|--extended) EXTENDED=1; shift ;;
    --strict) STRICT=1; shift ;;
    --no-strict) STRICT=0; shift ;;
    --argocd-ns) ARGOCD_NS="${2:-}"; shift 2 ;;
    --httproute-ns) HTTPROUTE_NS="${2:-}"; shift 2 ;;
    --httproute) HTTPROUTE_NAME="${2:-}"; shift 2 ;;
    --sso-ns) SSO_NS="${2:-}"; shift 2 ;;
    --oauth2-proxy) OAUTH2_PROXY_NAME="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -n "${APP}" ]] || { usage; fail "--app is required"; }

if [[ -n "${TFVARS_FILE}" && ! -f "${TFVARS_FILE}" ]]; then
  if [[ -f "${STACK_DIR}/${TFVARS_FILE}" ]]; then
    TFVARS_FILE="${STACK_DIR}/${TFVARS_FILE}"
  fi
fi

tfvar_get() {
  local file="$1"
  local key="$2"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo ""
    return 0
  fi
  # Use last occurrence to mirror var-file override semantics.
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true
}

if [[ -z "${ARGOCD_NS}" ]]; then
  ARGOCD_NS="$(tfvar_get "${TFVARS_FILE}" argocd_namespace)"
fi
if [[ -z "${ARGOCD_NS}" ]]; then
  ARGOCD_NS="argocd"
fi

if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT="$(tfvar_get "${TFVARS_FILE}" gateway_https_host_port)"
fi
if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT="443"
fi

if [[ -z "${HOST}" ]]; then
  # Heuristic: many workloads use env subdomains (sentiment.dev, subnetcalc.uat, etc) while their
  # Argo app names use "-dev"/"-uat". Default HOST should "just work" for these too.
  if [[ "${HOST_SUFFIX}" == ".admin.127.0.0.1.sslip.io" && "${APP}" =~ -dev$ ]]; then
    base="${APP%-dev}"
    HOST="${base}.dev.127.0.0.1.sslip.io"
  elif [[ "${HOST_SUFFIX}" == ".admin.127.0.0.1.sslip.io" && "${APP}" =~ -uat$ ]]; then
    base="${APP%-uat}"
    HOST="${base}.uat.127.0.0.1.sslip.io"
  else
    HOST="${APP}${HOST_SUFFIX}"
  fi
fi

if [[ -z "${HTTPROUTE_NAME}" ]]; then
  HTTPROUTE_NAME="${APP}"
fi

if [[ -z "${OAUTH2_PROXY_NAME}" ]]; then
  OAUTH2_PROXY_NAME="oauth2-proxy-${APP}"
fi

require kubectl

oauth2_proxy_arg_of_interest() {
  case "$1" in
    --cookie-name*|--cookie-domain*|--email-domain*|--redirect-url*|--upstream*|--skip-auth-regex*|--set-authorization-header*|--pass-access-token*|--set-xauthrequest*|--pass-user-headers*|--login-url*|--oidc-issuer-url*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

section() {
  echo
  echo "== ${1}"
}

maybe() { "$@" 2>/dev/null || true; }

print_kv() {
  printf '%-18s %s\n' "$1:" "$2"
}

argocd_app_exists() {
  kubectl -n "${ARGOCD_NS}" get app "$1" >/dev/null 2>&1
}

print_argocd_app() {
  local app="$1"
  if ! argocd_app_exists "${app}"; then
    warn "Argo CD app ${ARGOCD_NS}/${app} not found"
    return 0
  fi
  local sync health msg
  sync="$(kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  msg="$(kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.status.operationState.message}' 2>/dev/null || true)"
  echo "app=${app} sync=${sync:-?} health=${health:-?}"
  if [[ -n "${msg}" && "${msg}" != "null" ]]; then
    echo "  opMessage=${msg}"
  fi
  if [[ "${health}" != "Healthy" || "${sync}" != "Synced" ]]; then
    fail_soft "Argo CD app ${app} not Synced/Healthy (sync=${sync:-?} health=${health:-?})"
  fi
}

get_app_destination_namespace() {
  local app="$1"
  if ! argocd_app_exists "${app}"; then
    echo ""
    return 0
  fi
  kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true
}

print_oauth2_proxy_args_summary() {
  local deploy="$1"
  local ns="$2"
  if ! kubectl -n "${ns}" get deploy "${deploy}" >/dev/null 2>&1; then
    return 0
  fi
  local args_lines
  args_lines="$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null || true)"
  if [[ -z "${args_lines}" ]]; then
    return 0
  fi

  echo "Deployment args (selected): ${ns}/${deploy}"
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] || continue
    if oauth2_proxy_arg_of_interest "${arg}"; then
      printf '  %s\n' "${arg}"
    fi
  done <<< "${args_lines}"
}

curl_local() {
  local url="$1"
  if ! have curl; then
    warn "curl not found; skipping local HTTPS probe"
    return 0
  fi
  echo "GET ${url}"
  # Unauthenticated: expect 302 to dex (SSO) or 401/403 depending on app.
  local hdr
  hdr="$(mktemp)"
  local code=""
  set +e
  code="$(curl -k -sS -o /dev/null -D "${hdr}" --max-time 15 \
    --resolve "${HOST}:${HOST_PORT}:${RESOLVE_IP}" \
    -w '%{http_code}' \
    "${url}")"
  rc=$?
  set -e
  sed -n '1,25p' "${hdr}" || true
  rm -f "${hdr}"
  if [[ "${rc}" -ne 0 ]]; then
    warn "curl failed (rc=${rc})"
    return 0
  fi
  if [[ "${code}" =~ ^5 ]]; then
    fail_soft "HTTP probe returned ${code} (gateway/upstream likely unhealthy)"
  fi
}

print_endpointslices_for_service() {
  local ns="$1"
  local svc="$2"
  if ! kubectl -n "${ns}" get svc "${svc}" >/dev/null 2>&1; then
    return 0
  fi
  echo "--- endpointslices (${ns}/${svc}) ---"
  kubectl -n "${ns}" get endpointslices -l "kubernetes.io/service-name=${svc}" -o wide 2>/dev/null || true
}

print_gateway_nginx_logs() {
  local pattern="$1"
  if kubectl -n platform-gateway get deploy platform-gateway-nginx >/dev/null 2>&1; then
    kubectl -n platform-gateway logs deploy/platform-gateway-nginx -c nginx --since="${SINCE}" --tail="${TAIL}" 2>/dev/null \
      | grep -E "${pattern}" || true
    return 0
  fi
  # Fallback: pods (if deployment name changes).
  for p in $(kubectl -n platform-gateway get pods -o name 2>/dev/null | sed 's|pod/||'); do
    kubectl -n platform-gateway logs "${p}" -c nginx --since="${SINCE}" --tail="${TAIL}" 2>/dev/null \
      | grep -E "${pattern}" || true
  done
}

section "Inputs"
print_kv "app" "${APP}"
print_kv "host" "${HOST}"
print_kv "path" "${PATH_TO_CHECK}"
print_kv "host_port" "${HOST_PORT}"
print_kv "resolve_ip" "${RESOLVE_IP}"
print_kv "argocd_ns" "${ARGOCD_NS}"
print_kv "httproute" "${HTTPROUTE_NS}/${HTTPROUTE_NAME}"
print_kv "oauth2_proxy" "${SSO_NS}/${OAUTH2_PROXY_NAME}"
if [[ -n "${TFVARS_FILE}" ]]; then
  print_kv "tfvars" "${TFVARS_FILE}"
fi

section "Cluster Reachability"
kubectl get ns >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
ok "kubectl can reach the cluster"

section "Local HTTPS Probe (unauthenticated)"
curl_local "https://${HOST}:${HOST_PORT}${PATH_TO_CHECK}"

section "Argo CD Applications"
print_argocd_app "app-of-apps"
print_argocd_app "platform-gateway-routes"
print_argocd_app "${APP}"
print_argocd_app "${OAUTH2_PROXY_NAME}"

APP_NS="$(get_app_destination_namespace "${APP}")"
if [[ -z "${APP_NS}" ]]; then
  # As a fallback, try the oauth2-proxy app (if the actual app is GitOps-managed and absent from ArgoCD).
  APP_NS="$(get_app_destination_namespace "${OAUTH2_PROXY_NAME}")"
fi

if [[ -n "${APP_NS}" ]]; then
  section "Pods (app namespace: ${APP_NS})"
  maybe kubectl -n "${APP_NS}" get pods -o wide
  if [[ "${EXTENDED}" -eq 1 ]]; then
    maybe kubectl -n "${APP_NS}" get deploy,sts,svc -o wide
  else
    maybe kubectl -n "${APP_NS}" get deploy,sts -o wide | grep -E "${APP}|signoz|clickhouse|otel" || true
  fi
else
  warn "Could not infer destination namespace from Argo CD for app=${APP}; skipping app namespace pod listing"
fi

section "Pods (SSO namespace: ${SSO_NS})"
maybe kubectl -n "${SSO_NS}" get pods -o wide | grep -E "(^NAME|dex|${OAUTH2_PROXY_NAME}|oauth2-proxy-)" || true

section "Services / EndpointSlices"
maybe kubectl -n "${SSO_NS}" get svc "${OAUTH2_PROXY_NAME}" -o wide
print_endpointslices_for_service "${SSO_NS}" "${OAUTH2_PROXY_NAME}"
if [[ -n "${APP_NS}" ]]; then
  # Best-effort: show services that look relevant in the destination namespace.
  maybe kubectl -n "${APP_NS}" get svc -o wide | grep -E "(^NAME|${APP}|signoz)" || true
fi

section "HTTPRoute"
if kubectl -n "${HTTPROUTE_NS}" get httproute "${HTTPROUTE_NAME}" >/dev/null 2>&1; then
  ok "HTTPRoute exists: ${HTTPROUTE_NS}/${HTTPROUTE_NAME}"
  if [[ "${EXTENDED}" -eq 1 ]]; then
    kubectl -n "${HTTPROUTE_NS}" get httproute "${HTTPROUTE_NAME}" -o yaml || true
  else
    maybe kubectl -n "${HTTPROUTE_NS}" get httproute "${HTTPROUTE_NAME}" -o wide
  fi
else
  warn "HTTPRoute not found: ${HTTPROUTE_NS}/${HTTPROUTE_NAME}"
  # Host-based lookup (best-effort).
  echo "HTTPRoute hostnames (searching for ${HOST}):"
  maybe kubectl -n "${HTTPROUTE_NS}" get httproute -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.hostnames[*]}{.}{" "}{end}{"\n"}{end}' | grep -F "${HOST}" || true
fi

section "Gateway Logs (nginx) grep"
# Include both the host and common failure patterns.
PATTERN="$(printf '%s' "${HOST}" | sed -E 's/[.[\()*+?{|^$\\]/\\&/g')"
print_gateway_nginx_logs "${PATTERN}|connect\\(\\) failed|upstream prematurely closed| 502 | 503 | 504 |signoz|oauth2-proxy" || true

tail_deploy_logs() {
  local ns="$1"
  local deploy="$2"
  if ! kubectl -n "${ns}" get deploy "${deploy}" >/dev/null 2>&1; then
    return 0
  fi
  echo
  echo "Logs tail: ${ns}/deploy/${deploy} (since=${SINCE})"
  maybe kubectl -n "${ns}" logs deploy/"${deploy}" --since="${SINCE}" --tail="${TAIL}"
}

section "oauth2-proxy Diagnostics"
if kubectl -n "${SSO_NS}" get deploy "${OAUTH2_PROXY_NAME}" >/dev/null 2>&1; then
  maybe kubectl -n "${SSO_NS}" get deploy "${OAUTH2_PROXY_NAME}" -o wide
  if [[ "${EXTENDED}" -eq 1 ]]; then
    maybe kubectl -n "${SSO_NS}" describe deploy "${OAUTH2_PROXY_NAME}" | sed -n '1,220p'
  fi
  print_oauth2_proxy_args_summary "${OAUTH2_PROXY_NAME}" "${SSO_NS}"
  echo
  echo "Logs tail: ${SSO_NS}/${OAUTH2_PROXY_NAME} (since=${SINCE})"
  maybe kubectl -n "${SSO_NS}" logs deploy/"${OAUTH2_PROXY_NAME}" --since="${SINCE}" --tail="${TAIL}"
else
  warn "No oauth2-proxy deployment found: ${SSO_NS}/${OAUTH2_PROXY_NAME} (app may not be SSO protected)"
fi

if [[ -n "${APP_NS}" && ( "${EXTENDED}" -eq 1 || "${APP}" == "signoz" ) ]]; then
  section "App Logs (best-effort)"
  if [[ "${APP}" == "signoz" ]]; then
    # Chart naming is fairly stable, but keep it best-effort.
    tail_deploy_logs "${APP_NS}" "signoz-frontend"
    tail_deploy_logs "${APP_NS}" "signoz-query-service"
    tail_deploy_logs "${APP_NS}" "signoz-otel-collector"
  else
    # Generic heuristic: tail logs from deployments whose name matches the app string.
    for d in $(kubectl -n "${APP_NS}" get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E "${APP}" || true); do
      tail_deploy_logs "${APP_NS}" "${d}"
    done
  fi
fi

section "Events (SSO + Gateway)"
maybe kubectl -n "${SSO_NS}" get events --sort-by=.lastTimestamp | tail -n 18
maybe kubectl -n platform-gateway get events --sort-by=.lastTimestamp | tail -n 18

if [[ "${FAILURES}" -gt 0 ]]; then
  warn "Failures: ${FAILURES}"
  if [[ "${STRICT}" -eq 1 ]]; then
    exit 1
  fi
else
  ok "No failures detected"
fi
