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

KIND_OIDC_RECOVERY_FORCE_RUN="${KIND_OIDC_RECOVERY_FORCE_RUN:-0}"

# shellcheck disable=SC2329
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Performs the explicit post-restart recovery step after the kind kube-apiserver
OIDC static-manifest patch. This validates and, when needed, repairs Kyverno,
the nginx-gateway controller, and the programmed Gateway state.

Safe to rerun: if the runtime dependencies are already healthy, the script exits
without restarting controllers.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would recover kind runtime dependencies after a kube-apiserver restart" "$@"

require_cmd kubectl

if [[ "${KIND_OIDC_RECOVERY_FORCE_RUN}" != "1" ]] && kind_oidc_post_restart_dependencies_healthy; then
  ok "post-restart runtime dependencies already healthy; skipping targeted recovery"
  exit 0
fi

if [[ "${KIND_OIDC_RECOVERY_FORCE_RUN}" == "1" ]]; then
  ok "forcing the explicit post-restart recovery flow"
fi

if [[ "${POST_APISERVER_RESTART_SETTLE_SECONDS}" =~ ^[0-9]+$ ]] && (( POST_APISERVER_RESTART_SETTLE_SECONDS > 0 )); then
  ok "allowing in-cluster controllers to reconnect after kube-apiserver restart (${POST_APISERVER_RESTART_SETTLE_SECONDS}s)"
  sleep "${POST_APISERVER_RESTART_SETTLE_SECONDS}"
fi

wait_for_deployment_recovery_after_apiserver_restart \
  "${KYVERNO_NAMESPACE}" \
  "${KYVERNO_ADMISSION_DEPLOY_NAME}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  "Kyverno admission controller (${KYVERNO_NAMESPACE}/${KYVERNO_ADMISSION_DEPLOY_NAME})"

wait_for_service_endpoints "${KYVERNO_NAMESPACE}" "${KYVERNO_ADMISSION_SERVICE}" "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  || fail "Kyverno admission service has no endpoints after kube-apiserver restart"

wait_for_deployment_recovery_after_apiserver_restart \
  "${KYVERNO_NAMESPACE}" \
  "${KYVERNO_CLEANUP_DEPLOY_NAME}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  "Kyverno cleanup controller (${KYVERNO_NAMESPACE}/${KYVERNO_CLEANUP_DEPLOY_NAME})"

# Cilium's Gateway controller lives in cilium-operator, and the data plane is
# the Envoy inside cilium-agent. There is no gateway control-plane Deployment to
# restart and no gateway Service with endpoints to wait for; recycling the
# operator is what re-establishes the watch after the apiserver restart.
restart_deployment "${CILIUM_NAMESPACE}" "${CILIUM_OPERATOR_DEPLOY_NAME}" \
  "cilium operator (${CILIUM_NAMESPACE}/${CILIUM_OPERATOR_DEPLOY_NAME})"

ok "waiting for cilium operator after kube-apiserver restart"
if ! wait_for_deployment_rollout_with_early_recycle \
  "${CILIUM_NAMESPACE}" \
  "${CILIUM_OPERATOR_DEPLOY_NAME}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  "cilium operator (${CILIUM_NAMESPACE}/${CILIUM_OPERATOR_DEPLOY_NAME})"; then
  warn "cilium operator did not recover after initial restart; recycling pods once"
  recycle_deployment_pods \
    "${CILIUM_NAMESPACE}" \
    "${CILIUM_OPERATOR_DEPLOY_NAME}" \
    "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
    "cilium operator (${CILIUM_NAMESPACE}/${CILIUM_OPERATOR_DEPLOY_NAME})" \
    || fail "cilium operator did not recover after kube-apiserver restart"
fi

ok "verifying gateway is reprogrammed after kube-apiserver restart"
reconcile_end=$((SECONDS + GATEWAY_RECONCILE_WAIT_SECONDS))
while (( SECONDS < reconcile_end )); do
  gateway_programmed="$(gateway_condition_status "Programmed")"
  if [[ "${gateway_programmed}" == "True" ]]; then
    ok "gateway listener reprogrammed after kube-apiserver restart"
    exit 0
  fi

  sleep 5
done

kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" -o yaml || true
kubectl -n "${CILIUM_NAMESPACE}" logs "deploy/${CILIUM_OPERATOR_DEPLOY_NAME}" --tail=120 || true
fail "gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} did not recover after kube-apiserver restart"
