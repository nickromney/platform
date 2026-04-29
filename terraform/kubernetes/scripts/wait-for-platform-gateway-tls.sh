#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/kind-apiserver-oidc-lib.sh"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CERT_MANAGER_WEBHOOK_DEPLOYMENT="${CERT_MANAGER_WEBHOOK_DEPLOYMENT:-cert-manager-webhook}"
CERT_MANAGER_WEBHOOK_SERVICE="${CERT_MANAGER_WEBHOOK_SERVICE:-cert-manager-webhook}"
CERT_MANAGER_CONFIG_APP="${CERT_MANAGER_CONFIG_APP:-cert-manager-config}"
PLATFORM_GATEWAY_TLS_SECRET="${PLATFORM_GATEWAY_TLS_SECRET:-platform-gateway-tls}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-900}"
APP_REFRESH_INTERVAL_SECONDS="${APP_REFRESH_INTERVAL_SECONDS:-30}"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Wait for the cert-manager webhook, trigger Argo CD to retry cert-manager-config
reconciliation if needed, and only return once the platform gateway TLS secret
exists and the Gateway listener is programmed.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would wait for the platform gateway TLS certificate and listener readiness" "$@"

require_cmd kubectl

argocd_app_sync_status() {
  kubectl -n "${ARGOCD_NAMESPACE}" get app "${CERT_MANAGER_CONFIG_APP}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || true
}

argocd_app_health_status() {
  kubectl -n "${ARGOCD_NAMESPACE}" get app "${CERT_MANAGER_CONFIG_APP}" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || true
}

argocd_app_operation_message() {
  kubectl -n "${ARGOCD_NAMESPACE}" get app "${CERT_MANAGER_CONFIG_APP}" \
    -o jsonpath='{.status.operationState.message}' 2>/dev/null || true
}

refresh_cert_manager_config() {
  kubectl -n "${ARGOCD_NAMESPACE}" annotate app "${CERT_MANAGER_CONFIG_APP}" \
    argocd.argoproj.io/refresh=hard \
    --overwrite >/dev/null 2>&1 || true
}

ok "waiting for cert-manager webhook deployment (${CERT_MANAGER_NAMESPACE}/${CERT_MANAGER_WEBHOOK_DEPLOYMENT})"
if ! wait_for_deployment_rollout \
  "${CERT_MANAGER_NAMESPACE}" \
  "${CERT_MANAGER_WEBHOOK_DEPLOYMENT}" \
  "${WAIT_TIMEOUT_SECONDS}" \
  "cert-manager webhook (${CERT_MANAGER_NAMESPACE}/${CERT_MANAGER_WEBHOOK_DEPLOYMENT})"; then
  kubectl -n "${CERT_MANAGER_NAMESPACE}" get pods -o wide 2>/dev/null || true
  fail "cert-manager webhook deployment never became ready"
fi

if ! wait_for_service_endpoints \
  "${CERT_MANAGER_NAMESPACE}" \
  "${CERT_MANAGER_WEBHOOK_SERVICE}" \
  "${WAIT_TIMEOUT_SECONDS}"; then
  fail "cert-manager webhook service endpoints never became ready"
fi

ok "waiting for platform gateway TLS secret (${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_TLS_SECRET})"
end=$((SECONDS + WAIT_TIMEOUT_SECONDS))
next_refresh=0
last_sync=""
last_health=""
last_message=""
while (( SECONDS < end )); do
  if (( SECONDS >= next_refresh )); then
    refresh_cert_manager_config
    next_refresh=$((SECONDS + APP_REFRESH_INTERVAL_SECONDS))
  fi

  last_sync="$(argocd_app_sync_status)"
  last_health="$(argocd_app_health_status)"
  last_message="$(argocd_app_operation_message)"

  if kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get secret "${PLATFORM_GATEWAY_TLS_SECRET}" >/dev/null 2>&1; then
    gateway_programmed="$(gateway_condition_status Programmed)"
    gateway_accepted="$(gateway_condition_status Accepted)"
    if [[ "${gateway_programmed}" == "True" && "${gateway_accepted}" == "True" ]]; then
      ok "gateway listener programmed"
      ok "platform gateway TLS ready"
      exit 0
    fi
  fi

  sleep 5
done

warn "cert-manager-config sync=${last_sync:-?} health=${last_health:-?}"
if [[ -n "${last_message}" && "${last_message}" != "null" ]]; then
  warn "cert-manager-config message: ${last_message}"
fi
kubectl -n "${ARGOCD_NAMESPACE}" describe app "${CERT_MANAGER_CONFIG_APP}" 2>/dev/null || true
kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" -o yaml 2>/dev/null || true
kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get secret "${PLATFORM_GATEWAY_TLS_SECRET}" -o yaml 2>/dev/null || true
fail "platform gateway TLS never became ready"
