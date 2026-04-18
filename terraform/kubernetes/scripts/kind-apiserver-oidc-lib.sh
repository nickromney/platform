#!/usr/bin/env bash
# shellcheck shell=bash

KIND_APISERVER_OIDC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${KIND_APISERVER_OIDC_LIB_DIR}/../../.." && pwd)"
fi

INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*"; }

print_install_hint() {
  local tool="$1"

  if [[ -x "${INSTALL_HINTS}" ]]; then
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

wait_for_daemonset_rollout() {
  local namespace="${1}"
  local daemonset_name="${2}"
  local timeout_seconds="${3}"
  local description="${4:-daemonset ${namespace}/${daemonset_name}}"
  local end=$((SECONDS + timeout_seconds))

  while (( SECONDS < end )); do
    if kubectl -n "${namespace}" rollout status "daemonset/${daemonset_name}" --timeout=10s >/dev/null 2>&1; then
      ok "${description} ready"
      return 0
    fi
    sleep 5
  done

  warn "${description} not ready after ${timeout_seconds}s"
  kubectl -n "${namespace}" get daemonset "${daemonset_name}" -o wide 2>/dev/null || true
  kubectl -n "${namespace}" get pods -l "k8s-app=${daemonset_name}" -o wide 2>/dev/null || true
  return 1
}

service_has_endpoints() {
  local namespace="${1}"
  local service_name="${2}"
  local endpoints

  endpoints="$(
    kubectl -n "${namespace}" get endpoints "${service_name}" \
      -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true
  )"

  [[ -n "${endpoints// }" ]]
}

wait_for_service_endpoints() {
  local namespace="${1}"
  local service_name="${2}"
  local timeout_seconds="${3}"
  local end=$((SECONDS + timeout_seconds))

  while (( SECONDS < end )); do
    if service_has_endpoints "${namespace}" "${service_name}"; then
      local endpoints

      endpoints="$(
        kubectl -n "${namespace}" get endpoints "${service_name}" \
          -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true
      )"
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

deployment_rollout_ready_quick() {
  local namespace="${1}"
  local deploy_name="${2}"

  kubectl -n "${namespace}" rollout status "deploy/${deploy_name}" --timeout=5s >/dev/null 2>&1
}

wait_for_kube_apiserver_ready() {
  local timeout_seconds="${1}"
  local required_consecutive_successes="${2:-3}"
  local end=$((SECONDS + timeout_seconds))
  local consecutive_successes=0
  local probe_output=""
  local last_error=""
  local probe_status=0

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
  local attempt=1
  local delay=2
  local output=""
  local status=0

  shift

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
  local pod_name

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
  # shellcheck disable=SC2016
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

cilium_pod_for_node() {
  local node_name="${1}"

  kubectl -n kube-system get pods \
    -l "k8s-app=cilium" \
    --field-selector "spec.nodeName=${node_name}" \
    -o jsonpath='{range .items[0]}{.metadata.name}{end}' 2>/dev/null || true
}

recycle_cilium_on_nodes() {
  local node_names="${1}"
  local node_name
  local cilium_pod
  local recycled_any=0

  while IFS= read -r node_name; do
    [[ -n "${node_name}" ]] || continue

    cilium_pod="$(cilium_pod_for_node "${node_name}")"
    if [[ -z "${cilium_pod}" ]]; then
      warn "no Cilium pod found on ${node_name}; skipping node-local recycle"
      continue
    fi

    warn "recycling node-local Cilium for transient API connectivity recovery: ${node_name}/${cilium_pod}"
    kubectl -n kube-system delete pod "${cilium_pod}" --wait=false >/dev/null 2>&1 || true
    recycled_any=1
  done <<< "${node_names}"

  if [[ "${recycled_any}" -eq 0 ]]; then
    return 1
  fi

  wait_for_daemonset_rollout "kube-system" "cilium" "${GATEWAY_DEPLOY_WAIT_SECONDS}" "Cilium daemonset (kube-system/cilium)"
}

recycle_deployment_pods() {
  local namespace="${1}"
  local deploy_name="${2}"
  local timeout_seconds="${3}"
  local description="${4:-deployment ${namespace}/${deploy_name}}"
  local selector
  local pod_names
  local pod_name

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

deployment_api_connectivity_failure_nodes() {
  local namespace="${1}"
  local deploy_name="${2}"
  local selector
  local pod_names
  local pod_name
  local waiting_reasons
  local terminated_reasons
  local ready_statuses
  local pod_logs
  local previous_pod_logs
  local node_name

  selector="$(deployment_selector "${namespace}" "${deploy_name}")"
  if [[ -z "${selector}" ]]; then
    return 0
  fi

  pod_names="$(
    kubectl -n "${namespace}" get pods \
      -l "${selector}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  if [[ -z "${pod_names}" ]]; then
    return 0
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
    previous_pod_logs="$(kubectl -n "${namespace}" logs "${pod_name}" --previous --tail=40 2>/dev/null || true)"
    if ! printf '%s\n%s' "${pod_logs}" "${previous_pod_logs}" | grep -qiE \
      'failed to get server groups|failed to determine if .* is namespaced|connect: connection refused|dial tcp .*:443'; then
      continue
    fi

    node_name="$(kubectl -n "${namespace}" get pod "${pod_name}" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)"
    [[ -n "${node_name}" ]] || continue
    printf '%s\n' "${node_name}"
  done <<< "${pod_names}" | awk 'NF && !seen[$0]++'
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
  local recycled_cilium=0
  local selector
  local failed_nodes

  while (( SECONDS < end )); do
    if kubectl -n "${namespace}" rollout status "deploy/${deploy_name}" --timeout=10s >/dev/null 2>&1; then
      ok "${description} ready"
      return 0
    fi

    failed_nodes="$(deployment_api_connectivity_failure_nodes "${namespace}" "${deploy_name}")"
    if [[ -n "${failed_nodes}" && "${recycled_cilium}" -eq 0 ]]; then
      recycled_cilium=1
      recycle_cilium_on_nodes "${failed_nodes}" || return 1
      sleep 5
      continue
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

kind_oidc_post_restart_dependencies_healthy() {
  local gateway_programmed=""

  deployment_rollout_ready_quick "${KYVERNO_NAMESPACE}" "${KYVERNO_ADMISSION_DEPLOY_NAME}" || return 1
  service_has_endpoints "${KYVERNO_NAMESPACE}" "${KYVERNO_ADMISSION_SERVICE}" || return 1
  deployment_rollout_ready_quick "${KYVERNO_NAMESPACE}" "${KYVERNO_CLEANUP_DEPLOY_NAME}" || return 1
  deployment_rollout_ready_quick "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" || return 1
  service_has_endpoints "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_SERVICE}" || return 1
  gateway_programmed="$(gateway_condition_status "Programmed")"
  [[ "${gateway_programmed}" == "True" ]]
}
