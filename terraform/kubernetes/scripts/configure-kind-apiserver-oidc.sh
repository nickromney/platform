#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"
RENDER_KIND_APISERVER_OIDC_MANIFEST="${SCRIPT_DIR}/render-kind-apiserver-oidc-manifest.py"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*"; }
print_install_hint() {
  local tool="$1"
  if [ -x "${INSTALL_HINTS}" ]; then
    echo "Install hint:" >&2
    "${INSTALL_HINTS}" --execute --plain "${tool}" >&2 || true
  fi
}

require_cmd() {
  local tool="$1"
  if command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi
  print_install_hint "${tool}"
  fail "${tool} not found in PATH"
}

CLUSTER_NAME="${CLUSTER_NAME:-kind-local}"
PLATFORM_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_ADMIN_BASE_DOMAIN:-${PLATFORM_BASE_DOMAIN}}"
DEX_HOST="${DEX_HOST:-dex.${PLATFORM_ADMIN_BASE_DOMAIN}}"
DEX_NAMESPACE="${DEX_NAMESPACE:-sso}"
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://${DEX_HOST}/dex}"
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-headlamp}"
MKCERT_CA_DEST="${MKCERT_CA_DEST:-/etc/kubernetes/pki/mkcert-rootCA.pem}"
PLATFORM_GATEWAY_NAMESPACE="${PLATFORM_GATEWAY_NAMESPACE:-platform-gateway}"
PLATFORM_GATEWAY_INTERNAL_SVC="${PLATFORM_GATEWAY_INTERNAL_SVC:-platform-gateway-nginx-internal}"
GATEWAY_DEPLOY_NAME="${GATEWAY_DEPLOY_NAME:-platform-gateway-nginx}"
PLATFORM_GATEWAY_NAME="${PLATFORM_GATEWAY_NAME:-platform-gateway}"
PLATFORM_GATEWAY_TLS_SECRET="${PLATFORM_GATEWAY_TLS_SECRET:-platform-gateway-tls}"
NGINX_GATEWAY_NAMESPACE="${NGINX_GATEWAY_NAMESPACE:-nginx-gateway}"
NGINX_GATEWAY_DEPLOY_NAME="${NGINX_GATEWAY_DEPLOY_NAME:-nginx-gateway}"
NGINX_GATEWAY_SERVICE="${NGINX_GATEWAY_SERVICE:-nginx-gateway}"
KYVERNO_NAMESPACE="${KYVERNO_NAMESPACE:-kyverno}"
KYVERNO_ADMISSION_DEPLOY_NAME="${KYVERNO_ADMISSION_DEPLOY_NAME:-kyverno-admission-controller}"
KYVERNO_ADMISSION_SERVICE="${KYVERNO_ADMISSION_SERVICE:-kyverno-svc}"
KYVERNO_CLEANUP_DEPLOY_NAME="${KYVERNO_CLEANUP_DEPLOY_NAME:-kyverno-cleanup-controller}"
GATEWAY_DEPLOY_WAIT_SECONDS="${GATEWAY_DEPLOY_WAIT_SECONDS:-900}"
OIDC_DISCOVERY_WAIT_SECONDS="${OIDC_DISCOVERY_WAIT_SECONDS:-900}"
GATEWAY_RECONCILE_WAIT_SECONDS="${GATEWAY_RECONCILE_WAIT_SECONDS:-300}"
POST_APISERVER_RESTART_SETTLE_SECONDS="${POST_APISERVER_RESTART_SETTLE_SECONDS:-30}"

gateway_condition_status() {
  local condition_type="${1}"
  kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" \
    -o jsonpath="{range .status.conditions[?(@.type==\"${condition_type}\")]}{.status}{end}" 2>/dev/null || true
}

gateway_condition_message() {
  local condition_type="${1}"
  kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" \
    -o jsonpath="{range .status.conditions[?(@.type==\"${condition_type}\")]}{.message}{end}" 2>/dev/null || true
}

wait_for_deployment_rollout() {
  local namespace="${1}"
  local deploy_name="${2}"
  local timeout_seconds="${3}"
  local description="${4:-deployment ${namespace}/${deploy_name}}"
  local end=$((SECONDS + timeout_seconds))

  while (( SECONDS < end )); do
    if kubectl -n "${namespace}" rollout status "deploy/${deploy_name}" --timeout=10s >/dev/null 2>&1; then
      ok "${description} ready"
      return 0
    fi
    sleep 5
  done

  warn "${description} not ready after ${timeout_seconds}s"
  kubectl -n "${namespace}" get deploy "${deploy_name}" -o wide 2>/dev/null || true
  kubectl -n "${namespace}" get pods -l "app.kubernetes.io/name=${deploy_name}" -o wide 2>/dev/null || true
  return 1
}

wait_for_service_endpoints() {
  local namespace="${1}"
  local service_name="${2}"
  local timeout_seconds="${3}"
  local end=$((SECONDS + timeout_seconds))
  local endpoints

  while (( SECONDS < end )); do
    endpoints="$(
      kubectl -n "${namespace}" get endpoints "${service_name}" \
        -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true
    )"
    if [[ -n "${endpoints// }" ]]; then
      ok "service endpoints ready: ${namespace}/${service_name} -> ${endpoints}"
      return 0
    fi
    sleep 2
  done

  warn "service endpoints not ready after ${timeout_seconds}s: ${namespace}/${service_name}"
  kubectl -n "${namespace}" get svc "${service_name}" -o wide 2>/dev/null || true
  kubectl -n "${namespace}" get endpoints "${service_name}" -o wide 2>/dev/null || true
  kubectl -n "${namespace}" get endpointslices -l "kubernetes.io/service-name=${service_name}" -o wide 2>/dev/null || true
  return 1
}

wait_for_kube_apiserver_ready() {
  local timeout_seconds="${1}"
  local required_consecutive_successes="${2:-3}"
  local end=$((SECONDS + timeout_seconds))
  local consecutive_successes=0
  local probe_output=""
  local last_error=""

  while (( SECONDS < end )); do
    set +e
    probe_output="$(kubectl get --raw='/readyz' --request-timeout=5s 2>&1)"
    probe_status=$?
    set -e

    if [[ "${probe_status}" -eq 0 ]]; then
      consecutive_successes=$((consecutive_successes + 1))
      if (( consecutive_successes >= required_consecutive_successes )); then
        ok "kube-apiserver ready"
        return 0
      fi
      sleep 1
      continue
    fi

    last_error="${probe_output}"
    consecutive_successes=0
    sleep 2
  done

  if [[ -n "${last_error}" ]]; then
    warn "last kube-apiserver readiness probe error: ${last_error}"
  fi
  return 1
}

is_transient_kubectl_api_error() {
  local output="${1:-}"

  printf '%s' "${output}" | grep -qiE \
    'connection refused|context deadline exceeded|i/o timeout|timed out|tls handshake timeout|EOF|connection reset by peer|transport is closing|service unavailable|server is currently unable to handle the request|dial tcp|no route to host|client rate limiter Wait returned an error|Error from server \(Forbidden\): .*User "kubernetes-admin"|forbidden: User "kubernetes-admin"'
}

retry_webhook_fail() {
  local max_attempts="${1}"
  shift

  local attempt=1
  local delay=2
  local output
  local status

  while true; do
    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e

    if [[ "${status}" -eq 0 ]]; then
      if [[ -n "${output}" ]]; then
        printf '%s\n' "${output}"
      fi
      return 0
    fi

    if printf '%s' "${output}" | grep -qE 'failed calling webhook|no endpoints available for service|connect: connection refused|kyverno-svc|kyverno\.svc-fail'; then
      if (( attempt >= max_attempts )); then
        printf '%s\n' "${output}" >&2
        return "${status}"
      fi
      warn "admission webhook unavailable; retrying (${attempt}/${max_attempts}) after ${delay}s"
      sleep "${delay}"
      attempt=$((attempt + 1))
      delay=$((delay * 2))
      if (( delay > 30 )); then
        delay=30
      fi
      continue
    fi

    printf '%s\n' "${output}" >&2
    return "${status}"
  done
}

lookup_deployment_state() {
  local namespace="${1}"
  local deploy_name="${2}"
  local timeout_seconds="${3:-60}"
  local description="${4:-deployment ${namespace}/${deploy_name}}"
  local end=$((SECONDS + timeout_seconds))
  local output=""
  local status=0
  local last_error=""

  while (( SECONDS < end )); do
    set +e
    output="$(kubectl -n "${namespace}" get deploy "${deploy_name}" -o name 2>&1)"
    status=$?
    set -e

    if [[ "${status}" -eq 0 ]]; then
      return 0
    fi

    if printf '%s' "${output}" | grep -qiE '(not found|NotFound)'; then
      return 1
    fi

    if is_transient_kubectl_api_error "${output}"; then
      last_error="${output}"
      sleep 2
      continue
    fi

    warn "unexpected kubectl error while checking ${description}: ${output}"
    return 2
  done

  if [[ -n "${last_error}" ]]; then
    warn "timed out waiting for kube-apiserver to answer deployment lookup for ${description}: ${last_error}"
  else
    warn "timed out waiting for kube-apiserver to answer deployment lookup for ${description}"
  fi
  return 2
}

restart_deployment() {
  local namespace="${1}"
  local deploy_name="${2}"
  local description="${3:-deployment ${namespace}/${deploy_name}}"
  local lookup_status=0

  set +e
  lookup_deployment_state "${namespace}" "${deploy_name}" 60 "${description}"
  lookup_status=$?
  set -e

  case "${lookup_status}" in
    0)
      ;;
    1)
      warn "${description} not found; skipping controlled restart"
      return 0
      ;;
    *)
      fail "could not verify ${description} after kube-apiserver restart"
      ;;
  esac

  ok "restarting ${description}"
  retry_webhook_fail 12 kubectl -n "${namespace}" rollout restart "deploy/${deploy_name}" >/dev/null
}

recycle_gateway_data_plane() {
  local pod_names

  pod_names="$(
    kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get pods \
      -l "app.kubernetes.io/name=${GATEWAY_DEPLOY_NAME}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  if [[ -z "${pod_names}" ]]; then
    warn "no pods found for ${PLATFORM_GATEWAY_NAMESPACE}/${GATEWAY_DEPLOY_NAME}; waiting for deployment rollout instead"
  else
    while IFS= read -r pod_name; do
      [[ -n "${pod_name}" ]] || continue
      warn "recycling gateway data-plane pod: ${PLATFORM_GATEWAY_NAMESPACE}/${pod_name}"
      kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" delete pod "${pod_name}" --wait=false >/dev/null 2>&1 || true
    done <<< "${pod_names}"
  fi

  wait_for_deployment_rollout \
    "${PLATFORM_GATEWAY_NAMESPACE}" \
    "${GATEWAY_DEPLOY_NAME}" \
    "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
    "gateway data plane (${PLATFORM_GATEWAY_NAMESPACE}/${GATEWAY_DEPLOY_NAME})"
}

deployment_selector() {
  local namespace="${1}"
  local deploy_name="${2}"
  local selector=""
  local status=0

  # Post-apiserver-restart lookups can briefly fail under pipefail; treat that
  # as "no selector yet" so the higher-level recovery logic can retry or skip.
  set +e
  selector="$(
    kubectl -n "${namespace}" get deploy "${deploy_name}" \
      -o go-template='{{ range $k,$v := .spec.selector.matchLabels }}{{ printf "%s=%s\n" $k $v }}{{ end }}' 2>/dev/null \
      | paste -sd, -
  )"
  status=$?
  set -e

  if [[ "${status}" -ne 0 ]]; then
    selector=""
  fi

  printf '%s' "${selector}"
}

recycle_deployment_pods() {
  local namespace="${1}"
  local deploy_name="${2}"
  local timeout_seconds="${3}"
  local description="${4:-deployment ${namespace}/${deploy_name}}"
  local selector
  local pod_names

  selector="$(deployment_selector "${namespace}" "${deploy_name}")"
  if [[ -z "${selector}" ]]; then
    warn "no selector found for ${description}; waiting for deployment rollout instead"
    wait_for_deployment_rollout "${namespace}" "${deploy_name}" "${timeout_seconds}" "${description}"
    return $?
  fi

  pod_names="$(
    kubectl -n "${namespace}" get pods \
      -l "${selector}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  if [[ -z "${pod_names}" ]]; then
    warn "no pods found for ${description}; waiting for deployment rollout instead"
  else
    while IFS= read -r pod_name; do
      [[ -n "${pod_name}" ]] || continue
      warn "recycling ${description} pod: ${namespace}/${pod_name}"
      kubectl -n "${namespace}" delete pod "${pod_name}" --wait=false >/dev/null 2>&1 || true
    done <<< "${pod_names}"
  fi

  wait_for_deployment_rollout "${namespace}" "${deploy_name}" "${timeout_seconds}" "${description}"
}

deployment_pods_need_early_recycle() {
  local namespace="${1}"
  local deploy_name="${2}"
  local selector
  local pod_names
  local pod_name
  local waiting_reasons
  local terminated_reasons
  local ready_statuses
  local pod_logs

  selector="$(deployment_selector "${namespace}" "${deploy_name}")"
  if [[ -z "${selector}" ]]; then
    return 1
  fi

  pod_names="$(
    kubectl -n "${namespace}" get pods \
      -l "${selector}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  if [[ -z "${pod_names}" ]]; then
    return 1
  fi

  while IFS= read -r pod_name; do
    [[ -n "${pod_name}" ]] || continue

    waiting_reasons="$(
      kubectl -n "${namespace}" get pod "${pod_name}" \
        -o jsonpath='{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}' 2>/dev/null || true
    )"
    terminated_reasons="$(
      kubectl -n "${namespace}" get pod "${pod_name}" \
        -o jsonpath='{range .status.containerStatuses[*]}{.lastState.terminated.reason}{" "}{end}' 2>/dev/null || true
    )"
    ready_statuses="$(
      kubectl -n "${namespace}" get pod "${pod_name}" \
        -o jsonpath='{range .status.containerStatuses[*]}{.ready}{" "}{end}' 2>/dev/null || true
    )"

    if [[ "${waiting_reasons}" != *"CrashLoopBackOff"* \
      && "${terminated_reasons}" != *"Error"* \
      && " ${ready_statuses} " != *" false "* ]]; then
      continue
    fi

    pod_logs="$(kubectl -n "${namespace}" logs "${pod_name}" --tail=40 2>/dev/null || true)"
    if printf '%s' "${pod_logs}" | grep -qiE \
      'failed to get server groups|connect: connection refused|dial tcp .*:443'; then
      warn "detected transient API connectivity crash in ${namespace}/${pod_name}; recycling controller pods early"
      return 0
    fi
  done <<< "${pod_names}"

  return 1
}

wait_for_deployment_rollout_with_early_recycle() {
  local namespace="${1}"
  local deploy_name="${2}"
  local timeout_seconds="${3}"
  local description="${4:-deployment ${namespace}/${deploy_name}}"
  local end=$((SECONDS + timeout_seconds))
  local recycled=0

  while (( SECONDS < end )); do
    if kubectl -n "${namespace}" rollout status "deploy/${deploy_name}" --timeout=10s >/dev/null 2>&1; then
      ok "${description} ready"
      return 0
    fi

    if [[ "${recycled}" -eq 0 ]] && deployment_pods_need_early_recycle "${namespace}" "${deploy_name}"; then
      recycled=1
      recycle_deployment_pods "${namespace}" "${deploy_name}" "${timeout_seconds}" "${description}" || return 1
      return 0
    fi

    sleep 5
  done

  warn "${description} not ready after ${timeout_seconds}s"
  kubectl -n "${namespace}" get deploy "${deploy_name}" -o wide 2>/dev/null || true
  selector="$(deployment_selector "${namespace}" "${deploy_name}")"
  if [[ -n "${selector}" ]]; then
    kubectl -n "${namespace}" get pods -l "${selector}" -o wide 2>/dev/null || true
  fi
  return 1
}

wait_for_deployment_recovery_after_apiserver_restart() {
  local namespace="${1}"
  local deploy_name="${2}"
  local timeout_seconds="${3}"
  local description="${4:-deployment ${namespace}/${deploy_name}}"
  local lookup_status=0

  set +e
  lookup_deployment_state "${namespace}" "${deploy_name}" 60 "${description}"
  lookup_status=$?
  set -e

  case "${lookup_status}" in
    0)
      ;;
    1)
      warn "${description} not found; skipping post-restart recovery wait"
      return 0
      ;;
    *)
      fail "could not verify ${description} after kube-apiserver restart"
      ;;
  esac

  ok "waiting for ${description} after kube-apiserver restart"
  if ! wait_for_deployment_rollout_with_early_recycle "${namespace}" "${deploy_name}" "${timeout_seconds}" "${description}"; then
    warn "${description} did not recover after initial wait; recycling controller pods once"
    recycle_deployment_pods "${namespace}" "${deploy_name}" "${timeout_seconds}" "${description}" \
      || fail "${description} did not recover after kube-apiserver restart"
  fi
}

usage() {
  cat <<'EOF'
Usage: configure-kind-apiserver-oidc.sh [--dry-run] [--execute]

Configures the kind control-plane kube-apiserver static manifest for OIDC auth
against the local Dex instance (so Headlamp OIDC tokens work against the K8s API).

Environment variables:
  CLUSTER_NAME
  DEX_HOST
  DEX_NAMESPACE
  OIDC_ISSUER_URL
  OIDC_CLIENT_ID
  MKCERT_CA_DEST
  PLATFORM_GATEWAY_NAMESPACE
  PLATFORM_GATEWAY_INTERNAL_SVC
  GATEWAY_DEPLOY_NAME
  PLATFORM_GATEWAY_NAME
  PLATFORM_GATEWAY_TLS_SECRET
  NGINX_GATEWAY_NAMESPACE
  NGINX_GATEWAY_DEPLOY_NAME
  NGINX_GATEWAY_SERVICE
  KYVERNO_NAMESPACE
  KYVERNO_ADMISSION_DEPLOY_NAME
  KYVERNO_ADMISSION_SERVICE
  KYVERNO_CLEANUP_DEPLOY_NAME
  GATEWAY_DEPLOY_WAIT_SECONDS
  OIDC_DISCOVERY_WAIT_SECONDS
  GATEWAY_RECONCILE_WAIT_SECONDS
  POST_APISERVER_RESTART_SETTLE_SECONDS

This is a local-dev helper; it mutates the kind node container and will restart
the kube-apiserver.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would configure the kind kube-apiserver OIDC settings" "$@"

require_cmd kind
require_cmd kubectl
require_cmd docker
require_cmd curl

if ! command -v mkcert >/dev/null 2>&1; then
  warn "mkcert not found; skipping apiserver OIDC configuration"
  print_install_hint "mkcert"
  exit 0
fi

CAROOT="$(mkcert -CAROOT)"
CA_CERT="${CAROOT}/rootCA.pem"
if [[ ! -f "${CA_CERT}" ]]; then
  warn "mkcert CA cert not found at ${CA_CERT}; skipping apiserver OIDC configuration"
  exit 0
fi

CONTROL_PLANE_NODE="$(kind get nodes --name "${CLUSTER_NAME}" | grep -E 'control-plane$|control-plane' | head -n 1)"
if [[ -z "${CONTROL_PLANE_NODE}" ]]; then
  CONTROL_PLANE_NODE="$(kind get nodes --name "${CLUSTER_NAME}" | head -n 1)"
fi
if [[ -z "${CONTROL_PLANE_NODE}" ]]; then
  fail "No kind nodes found for cluster ${CLUSTER_NAME}"
fi

ok "kind control-plane node: ${CONTROL_PLANE_NODE}"

GATEWAY_IP="$(kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get svc "${PLATFORM_GATEWAY_INTERNAL_SVC}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
if [[ -z "${GATEWAY_IP}" ]]; then
  fail "Could not determine clusterIP for svc ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_INTERNAL_SVC}"
fi

ok "gateway internal clusterIP: ${GATEWAY_IP}"

ok "ensuring ${DEX_HOST} resolves inside kind node"
docker exec "${CONTROL_PLANE_NODE}" sh -lc "grep -qE '^[0-9.]+[[:space:]]+${DEX_HOST}(\\s|$)' /etc/hosts || echo '${GATEWAY_IP} ${DEX_HOST}' >> /etc/hosts"

ok "copying mkcert root CA into kind node: ${MKCERT_CA_DEST}"
docker cp "${CA_CERT}" "${CONTROL_PLANE_NODE}:${MKCERT_CA_DEST}"

ok "waiting for gateway data plane (${PLATFORM_GATEWAY_NAMESPACE}/${GATEWAY_DEPLOY_NAME})"
if ! wait_for_deployment_rollout \
  "${PLATFORM_GATEWAY_NAMESPACE}" \
  "${GATEWAY_DEPLOY_NAME}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  "gateway data plane (${PLATFORM_GATEWAY_NAMESPACE}/${GATEWAY_DEPLOY_NAME})"; then
  warn "gateway data plane not ready after ${GATEWAY_DEPLOY_WAIT_SECONDS}s"
  kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get pods -l "gateway.networking.k8s.io/gateway-name=platform-gateway" -o wide 2>/dev/null || true
  fail "gateway data plane never became ready; aborting OIDC apiserver configuration"
fi

ok "waiting for TLS secret ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_TLS_SECRET}"
tls_end=$((SECONDS + GATEWAY_DEPLOY_WAIT_SECONDS))
while (( SECONDS < tls_end )); do
  if kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get secret "${PLATFORM_GATEWAY_TLS_SECRET}" >/dev/null 2>&1; then
    ok "gateway TLS secret present"
    break
  fi
  sleep 2
done
if (( SECONDS >= tls_end )); then
  kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get secret "${PLATFORM_GATEWAY_TLS_SECRET}" >/dev/null 2>&1 || true
  fail "gateway TLS secret ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_TLS_SECRET} was never created"
fi

ok "waiting for Gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} to be programmed"
gw_prog_end=$((SECONDS + GATEWAY_DEPLOY_WAIT_SECONDS))
while (( SECONDS < gw_prog_end )); do
  gateway_programmed="$(kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" -o jsonpath='{range .status.conditions[?(@.type=="Programmed")]}{.status}{end}' 2>/dev/null || true)"
  gateway_accepted="$(kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" -o jsonpath='{range .status.conditions[?(@.type=="Accepted")]}{.status}{end}' 2>/dev/null || true)"
  if [[ "${gateway_programmed}" == "True" && "${gateway_accepted}" == "True" ]]; then
    ok "gateway listener programmed"
    break
  fi
  sleep 2
done
if (( SECONDS >= gw_prog_end )); then
  kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" -o yaml || true
  fail "gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} never became programmed"
fi

ok "waiting for Dex deployment (${DEX_NAMESPACE}/dex)"
if ! wait_for_deployment_rollout \
  "${DEX_NAMESPACE}" \
  "dex" \
  "${OIDC_DISCOVERY_WAIT_SECONDS}" \
  "Dex deployment (${DEX_NAMESPACE}/dex)"; then
  kubectl -n "${DEX_NAMESPACE}" get all -o wide 2>/dev/null || true
  fail "Dex deployment never became ready"
fi

if ! wait_for_service_endpoints \
  "${DEX_NAMESPACE}" \
  "dex" \
  "${OIDC_DISCOVERY_WAIT_SECONDS}"; then
  fail "Dex service endpoints never became ready"
fi

ok "waiting for OIDC issuer discovery endpoint from kind control-plane node"
end=$((SECONDS + OIDC_DISCOVERY_WAIT_SECONDS))
while (( SECONDS < end )); do
  if docker exec "${CONTROL_PLANE_NODE}" sh -lc "curl -fsS --max-time 5 --cacert '${MKCERT_CA_DEST}' '${OIDC_ISSUER_URL}/.well-known/openid-configuration' >/dev/null"; then
    ok "OIDC issuer reachable from kind node: ${OIDC_ISSUER_URL}"
    break
  fi
  sleep 2
done

if (( SECONDS >= end )); then
  fail "timed out waiting for ${OIDC_ISSUER_URL}/.well-known/openid-configuration (from kind node)"
fi

MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
ok "patching kube-apiserver manifest for OIDC (idempotent): ${MANIFEST}"

ORIGINAL_MANIFEST_LOCAL="$(mktemp "${TMPDIR:-/tmp}/kube-apiserver-manifest.original.XXXXXX")"
RENDERED_MANIFEST_LOCAL="$(mktemp "${TMPDIR:-/tmp}/kube-apiserver-manifest.rendered.XXXXXX")"
CONTAINER_MANIFEST_BACKUP="${MANIFEST}.pre-oidc-backup"
CONTAINER_MANIFEST_CANDIDATE="${MANIFEST}.oidc-candidate"

trap 'rm -f "${ORIGINAL_MANIFEST_LOCAL}" "${RENDERED_MANIFEST_LOCAL}"; docker exec "${CONTROL_PLANE_NODE}" rm -f "${CONTAINER_MANIFEST_CANDIDATE}" >/dev/null 2>&1 || true' EXIT

docker cp "${CONTROL_PLANE_NODE}:${MANIFEST}" "${ORIGINAL_MANIFEST_LOCAL}"

[[ -f "${RENDER_KIND_APISERVER_OIDC_MANIFEST}" ]] || fail "render helper not found at ${RENDER_KIND_APISERVER_OIDC_MANIFEST}"
require_cmd python3

python3 \
  "${RENDER_KIND_APISERVER_OIDC_MANIFEST}" \
  "${ORIGINAL_MANIFEST_LOCAL}" \
  "${RENDERED_MANIFEST_LOCAL}" \
  "${OIDC_ISSUER_URL}" \
  "${OIDC_CLIENT_ID}" \
  "${MKCERT_CA_DEST}" \
  "${DEX_HOST}" \
  "${GATEWAY_IP}"

if ! kubectl create --dry-run=client --validate=false -f "${RENDERED_MANIFEST_LOCAL}" >/dev/null 2>&1; then
  kubectl create --dry-run=client --validate=false -f "${RENDERED_MANIFEST_LOCAL}" >/dev/null
fi

if cmp -s "${ORIGINAL_MANIFEST_LOCAL}" "${RENDERED_MANIFEST_LOCAL}"; then
  ok "kube-apiserver manifest already matches desired OIDC config; skipping restart"
  exit 0
fi

ok "installing kube-apiserver OIDC manifest update with rollback safety"
docker exec "${CONTROL_PLANE_NODE}" cp "${MANIFEST}" "${CONTAINER_MANIFEST_BACKUP}"
docker cp "${RENDERED_MANIFEST_LOCAL}" "${CONTROL_PLANE_NODE}:${CONTAINER_MANIFEST_CANDIDATE}"
docker exec "${CONTROL_PLANE_NODE}" mv "${CONTAINER_MANIFEST_CANDIDATE}" "${MANIFEST}"

ok "waiting for kube-apiserver readiness (this may take ~30s)"
if ! wait_for_kube_apiserver_ready 120 3; then
  warn "kube-apiserver did not recover after OIDC patch; restoring previous manifest"
  docker exec "${CONTROL_PLANE_NODE}" sh -lc \
    "cp '${CONTAINER_MANIFEST_BACKUP}' '${CONTAINER_MANIFEST_CANDIDATE}' && mv '${CONTAINER_MANIFEST_CANDIDATE}' '${MANIFEST}'"
  if wait_for_kube_apiserver_ready 120 3; then
    fail "timed out waiting for kube-apiserver readiness after OIDC patch; restored previous manifest"
  fi
  fail "timed out waiting for kube-apiserver readiness after OIDC patch, and rollback also failed"
fi

docker exec "${CONTROL_PLANE_NODE}" rm -f "${CONTAINER_MANIFEST_BACKUP}" >/dev/null 2>&1 || true

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

restart_deployment "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" "nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})"

ok "waiting for nginx gateway control plane after kube-apiserver restart"
if ! wait_for_deployment_rollout_with_early_recycle \
  "${NGINX_GATEWAY_NAMESPACE}" \
  "${NGINX_GATEWAY_DEPLOY_NAME}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  "nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})"; then
  warn "nginx gateway control plane did not recover after initial restart; recycling controller pods once"
  recycle_deployment_pods \
    "${NGINX_GATEWAY_NAMESPACE}" \
    "${NGINX_GATEWAY_DEPLOY_NAME}" \
    "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
    "nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})" \
    || fail "nginx gateway control plane did not recover after kube-apiserver restart"
fi

wait_for_service_endpoints "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_SERVICE}" "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  || fail "nginx gateway control plane service has no endpoints after kube-apiserver restart"

ok "verifying gateway is reprogrammed after kube-apiserver restart"
reconcile_end=$((SECONDS + GATEWAY_RECONCILE_WAIT_SECONDS))
recycled_gateway_data_plane=0
while (( SECONDS < reconcile_end )); do
  gateway_programmed="$(gateway_condition_status "Programmed")"
  gateway_message="$(gateway_condition_message "Programmed")"
  if [[ "${gateway_programmed}" == "True" ]]; then
    ok "gateway listener reprogrammed after kube-apiserver restart"
    exit 0
  fi

  if [[ "${recycled_gateway_data_plane}" -eq 0 ]] \
    && [[ "${gateway_message}" == *"failure to reload nginx"* || "${gateway_message}" == *"dial tcp"* || "${gateway_message}" == *"connect: connection refused"* ]]; then
    warn "gateway remained unprogrammed after kube-apiserver restart: ${gateway_message}"
    recycle_gateway_data_plane || fail "gateway data plane failed to recover after recycle"
    recycled_gateway_data_plane=1
  fi

  sleep 5
done

kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" -o yaml || true
kubectl -n "${NGINX_GATEWAY_NAMESPACE}" logs "deploy/${NGINX_GATEWAY_DEPLOY_NAME}" --tail=120 || true
fail "gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} did not recover after kube-apiserver restart"
