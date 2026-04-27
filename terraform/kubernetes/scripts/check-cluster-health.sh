#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/platform-env.sh"

usage() {
  cat <<EOF
Usage: check-cluster-health.sh [--var-file PATH]... [--show-urls] [--dry-run] [--execute]

Runs the stack-aware cluster health diagnostics for the current platform
environment.

$(shell_cli_standard_options)
EOF
}

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'
APP_REFRESH_INTERVAL_SECONDS="${APP_REFRESH_INTERVAL_SECONDS:-30}"

fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }
FAILURES=0
fail_soft() { echo "${RED}✖${NC} $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "${YELLOW}⚠${NC} $*"; }
ok() { echo "${GREEN}✔${NC} $*"; }

node_not_ready_count() {
  local statuses
  statuses="$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' || true)"
  if [[ -z "${statuses}" ]]; then
    echo 0
    return 0
  fi
  printf '%s\n' "${statuses}" | awk '$1 != "Ready" {count++} END {print count+0}'
}

wait_for_all_nodes_ready() {
  local timeout_seconds="${1:-60}"
  local end=$((SECONDS + timeout_seconds))

  while (( SECONDS < end )); do
    if [[ "$(node_not_ready_count)" -eq 0 ]]; then
      return 0
    fi
    sleep 5
  done

  [[ "$(node_not_ready_count)" -eq 0 ]]
}

argocd_app_has_only_future_stage_namespace_gaps() {
  local ns="$1"
  local app="$2"
  local unsynced kind resource_ns msg

  if [[ "${app}" != "cilium-policies" ]] || stage_ge 700; then
    return 1
  fi

  unsynced=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{range .status.operationState.syncResult.resources[?(@.status!="Synced")]}{.kind}{"\t"}{.namespace}{"\t"}{.message}{"\n"}{end}' 2>/dev/null || true)
  [[ -n "${unsynced}" ]] || return 1

  while IFS=$'\t' read -r kind resource_ns msg; do
    [[ -n "${kind}" ]] || continue
    if [[ "${kind}" != "CiliumNetworkPolicy" ]]; then
      return 1
    fi
    if [[ "${resource_ns}" != "dev" && "${resource_ns}" != "uat" ]]; then
      return 1
    fi
    if [[ "${msg}" != "namespaces \"${resource_ns}\" not found" ]]; then
      return 1
    fi
  done <<< "${unsynced}"

  return 0
}

argocd_app_allows_outofsync_if_healthy() {
  local ns="$1"
  local app="$2"

  [[ "${app}" == "app-of-apps" || "${app}" == "platform-gateway" ]] && return 0
  argocd_app_has_only_future_stage_namespace_gaps "${ns}" "${app}"
}

argocd_app_has_stale_aggregate_health() {
  local ns="$1"
  local app="$2"

  [[ "${app}" == "platform-gateway-routes" ]] || return 1
  if ! kubectl -n "${ns}" get app "${app}" >/dev/null 2>&1; then
    return 1
  fi

  local sync health op_phase conditions child_sync_drift child_bad_health op_rev sync_rev
  sync=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  [[ "${sync}" == "Synced" && "${health}" == "Degraded" ]] || return 1

  op_phase=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")
  [[ "${op_phase}" == "Succeeded" ]] || return 1

  conditions=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{range .status.conditions[*]}{.type}{"\n"}{end}' 2>/dev/null | awk 'NF' || true)
  [[ -z "${conditions}" ]] || return 1

  op_rev=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.operationState.syncResult.revision}' 2>/dev/null || echo "")
  sync_rev=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.sync.revision}' 2>/dev/null || echo "")
  if [[ -n "${op_rev}" && -n "${sync_rev}" && "${op_rev}" != "${sync_rev}" ]]; then
    return 1
  fi

  child_sync_drift=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{range .status.resources[?(@.status!="Synced")]}{.kind}{" "}{.namespace}{"/"}{.name}{" sync="}{.status}{"\n"}{end}' 2>/dev/null | awk 'NF' || true)
  [[ -z "${child_sync_drift}" ]] || return 1

  child_bad_health=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{range .status.resources[?(@.health.status!="Healthy")]}{.kind}{" "}{.namespace}{"/"}{.name}{" health="}{.health.status}{"\n"}{end}' 2>/dev/null | awk 'NF' || true)
  [[ -z "${child_bad_health}" ]] || return 1
}

argocd_refresh_app() {
  local ns="$1"
  local app="$2"

  kubectl -n "${ns}" annotate app "${app}" \
    argocd.argoproj.io/refresh=hard \
    --overwrite >/dev/null 2>&1 || true
}

argocd_app_needs_hard_refresh() {
  local ns="$1"
  local app="$2"

  if ! kubectl -n "${ns}" get app "${app}" >/dev/null 2>&1; then
    return 1
  fi

  local sync health comparison
  sync=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  comparison=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || echo "")

  if [[ -n "${comparison}" ]]; then
    return 0
  fi

  if [[ "${health}" != "Healthy" ]]; then
    return 0
  fi

  if [[ "${sync}" != "Synced" ]] && ! argocd_app_allows_outofsync_if_healthy "${ns}" "${app}"; then
    return 0
  fi

  return 1
}

argocd_app_is_settled() {
  local ns="$1"
  local app="$2"

  if ! kubectl -n "${ns}" get app "${app}" >/dev/null 2>&1; then
    return 0
  fi

  local sync health
  sync=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")

  if [[ "${health}" != "Healthy" ]]; then
    if argocd_app_has_stale_aggregate_health "${ns}" "${app}"; then
      return 0
    fi
    return 1
  fi

  if [[ "${sync}" != "Synced" ]] && ! argocd_app_allows_outofsync_if_healthy "${ns}" "${app}"; then
    return 1
  fi

  return 0
}

wait_for_argocd_apps_settled() {
  local ns="$1"
  local timeout_seconds="${2:-60}"
  local end=$((SECONDS + timeout_seconds))
  local next_refresh=0

  while (( SECONDS < end )); do
    local apps unsettled
    apps=$(kubectl -n "${ns}" get applications.argoproj.io -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort || true)
    if [[ -z "${apps}" ]]; then
      return 0
    fi

    unsettled=0
    while IFS= read -r app; do
      [[ -n "${app}" ]] || continue
      if ! argocd_app_is_settled "${ns}" "${app}"; then
        unsettled=1
        if (( SECONDS >= next_refresh )) && argocd_app_needs_hard_refresh "${ns}" "${app}"; then
          # Kind's control-plane restart can leave Argo app health/sync state stale
          # even after workloads are ready; a hard refresh converges the cache.
          argocd_refresh_app "${ns}" "${app}"
        fi
      fi
    done <<< "${apps}"

    if [[ "${unsettled}" -eq 0 ]]; then
      return 0
    fi

    if (( SECONDS >= next_refresh )); then
      next_refresh=$((SECONDS + APP_REFRESH_INTERVAL_SECONDS))
    fi

    sleep 5
  done

  return 1
}

wait_for_argocd_app_settled() {
  local ns="$1"
  local app="$2"
  local timeout_seconds="${3:-60}"
  local end=$((SECONDS + timeout_seconds))
  local next_refresh=0

  while (( SECONDS < end )); do
    if argocd_app_is_settled "${ns}" "${app}"; then
      return 0
    fi

    if (( SECONDS >= next_refresh )) && argocd_app_needs_hard_refresh "${ns}" "${app}"; then
      argocd_refresh_app "${ns}" "${app}"
      next_refresh=$((SECONDS + APP_REFRESH_INTERVAL_SECONDS))
    fi

    sleep 5
  done

  argocd_app_is_settled "${ns}" "${app}"
}

print_events() {
  local ns="$1"
  local n="${2:-12}"
  warn "Recent events (ns=${ns}, last ${n}):"
  kubectl -n "${ns}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n "${n}" || true
}

check_argocd_app() {
  local app="$1"
  local ns="$2"
  local allow_outofsync_if_healthy="${3:-false}"

  if argocd_app_allows_outofsync_if_healthy "${ns}" "${app}"; then
    allow_outofsync_if_healthy="true"
  fi

  if ! kubectl -n "${ns}" get app "${app}" >/dev/null 2>&1; then
    return 1
  fi

  if ! argocd_app_is_settled "${ns}" "${app}"; then
    wait_for_argocd_app_settled "${ns}" "${app}" 90 || true
  fi

  local sync health
  sync=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  local op_phase op_rev sync_rev op_started
  op_phase=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")
  op_rev=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.operationState.syncResult.revision}' 2>/dev/null || echo "")
  sync_rev=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.sync.revision}' 2>/dev/null || echo "")
  op_started=$(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || echo "")

  if [[ "${health}" != "Healthy" ]]; then
    if argocd_app_has_stale_aggregate_health "${ns}" "${app}"; then
      ok "Argo CD app ${app} is Synced with stale aggregate Degraded health (child resources clean)"
      return 0
    fi
    fail_soft "Argo CD app ${app} not Healthy (sync=${sync}, health=${health})"
    warn "Argo CD app ${app} operation message: $(kubectl -n "${ns}" get app "${app}" -o jsonpath='{.status.operationState.message}' 2>/dev/null || echo "")"
    if [[ "${op_phase}" == "Running" && -n "${op_rev}" && -n "${sync_rev}" && "${op_rev}" != "${sync_rev}" ]]; then
      warn "Argo CD app ${app} has a stuck running operation pinned to an older revision:"
      warn "  operation.startedAt=${op_started:-?}"
      warn "  operation.revision=${op_rev}"
      warn "  desired.revision=${sync_rev}"
      warn "If this persists, terminate the operation and let automated sync retry:"
      warn "  kubectl -n ${ns} patch app ${app} --type merge -p '{\"operation\":null}'"
    fi
    warn "Argo CD app ${app} non-Healthy resources (kind ns/name sync health msg):"
    kubectl -n "${ns}" get app "${app}" -o jsonpath='{range .status.resources[?(@.health.status!="Healthy")]}{.kind}{" "}{.namespace}{"/"}{.name}{" sync="}{.status}{" health="}{.health.status}{" msg="}{.health.message}{"\n"}{end}' 2>/dev/null | head -n 30 || true
    print_events "${ns}" 10
    return 0
  fi

  if [[ "${sync}" != "Synced" ]]; then
    if [[ "${allow_outofsync_if_healthy}" == "true" ]]; then
      ok "Argo CD app ${app} is Healthy (sync=${sync}) (tolerated)"
      return 0
    fi
    fail_soft "Argo CD app ${app} not Synced (sync=${sync}, health=${health})"
    warn "Argo CD app ${app} conditions: $(kubectl -n "${ns}" get app "${app}" -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.message}{" | "}{end}' 2>/dev/null || echo "")"
    return 0
  fi

  ok "Argo CD app ${app} is Synced/Healthy"
}

check_all_argocd_apps() {
  local ns="$1"

  local apps
  apps=$(kubectl -n "${ns}" get applications.argoproj.io -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort || true)
  if [[ -z "${apps}" ]]; then
    return 0
  fi

  while IFS= read -r app; do
    [[ -z "${app}" ]] && continue
    check_argocd_app "${app}" "${ns}" "$( [[ "${app}" == "app-of-apps" || "${app}" == "platform-gateway" ]] && echo true || echo false )"
  done <<<"${apps}"
}

summarize_policy_posture() {
  echo ""
  echo "Policy posture (Cilium + Kyverno):"

  if ! section_active 600 "${EXPECT_POLICIES}"; then
    ok "Skipped until stage 600"
    return 0
  fi

  if [[ "${EXPECT_POLICIES}" != "true" ]]; then
    ok "Policy posture checks skipped (enable_policies=${EXPECT_POLICIES}${tfvars_hint})"
    return 0
  fi

  local cilium_clusterwide_lines cilium_namespaced_lines cilium_lines cilium_count=0 cilium_invalid=0
  cilium_clusterwide_lines=$(kubectl get ciliumclusterwidenetworkpolicies -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[?(@.type=="Valid")]}{.status}{end}{"\n"}{end}' 2>/dev/null || true)
  cilium_namespaced_lines=$(kubectl get ciliumnetworkpolicies -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{range .status.conditions[?(@.type=="Valid")]}{.status}{end}{"\n"}{end}' 2>/dev/null || true)
  cilium_lines="$(printf '%s\n%s\n' "${cilium_clusterwide_lines}" "${cilium_namespaced_lines}" | awk 'NF > 0')"
  if [[ -z "${cilium_lines}" ]]; then
    warn "No Cilium policy resources found"
  else
    while IFS=$'\t' read -r name valid; do
      [[ -z "${name}" ]] && continue
      cilium_count=$((cilium_count + 1))
      if [[ "${valid}" != "True" ]]; then
        cilium_invalid=$((cilium_invalid + 1))
        fail_soft "Cilium policy ${name} is not Valid (Valid=${valid:-<empty>})"
      fi
    done <<<"${cilium_lines}"
    if [[ "${cilium_invalid}" -eq 0 ]]; then
      ok "Cilium policy validation OK (${cilium_count} policy resource(s) across CCNP/CNP)"
    fi
  fi

  local kyverno_lines kyverno_count=0 kyverno_not_ready=0
  kyverno_lines=$(kubectl get clusterpolicies.kyverno.io -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${kyverno_lines}" ]]; then
    warn "No Kyverno ClusterPolicy resources found"
  else
    while IFS=$'\t' read -r name ready; do
      [[ -z "${name}" ]] && continue
      kyverno_count=$((kyverno_count + 1))
      if [[ "${ready}" != "True" ]]; then
        kyverno_not_ready=$((kyverno_not_ready + 1))
        fail_soft "Kyverno policy ${name} is not Ready (Ready=${ready:-<empty>})"
      fi
    done <<<"${kyverno_lines}"
    if [[ "${kyverno_not_ready}" -eq 0 ]]; then
      ok "Kyverno policy readiness OK (${kyverno_count} policy resource(s))"
    fi
  fi

  local pr_fail_lines cpr_fail_lines issue_count=0 line
  pr_fail_lines=$(kubectl get policyreport -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{.summary.fail}{"\n"}{end}' 2>/dev/null | awk -F'\t' '$2+0>0 {print $1"\tfail="$2}' || true)
  cpr_fail_lines=$(kubectl get clusterpolicyreport -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.summary.fail}{"\n"}{end}' 2>/dev/null | awk -F'\t' '$2+0>0 {print $1"\tfail="$2}' || true)

  if have_cmd jq; then
    local pr_actionable_lines pr_stale_count=0
    pr_actionable_lines=$(kubectl get policyreport -A -o json 2>/dev/null | jq -r '
      .items[]
      | .metadata.namespace as $ns
      | .metadata.name as $name
      | [(.results[]? | select(.result=="fail") | (.resources // [])[]? | (.kind + "/" + .name))] as $resources
      | select(($resources | length) > 0)
      | "\($ns)/\($name)\tfail=\(.summary.fail // 0)\tresources=\(($resources | unique | join(",")))"
    ' || true)
    pr_stale_count=$(kubectl get policyreport -A -o json 2>/dev/null | jq -r '
      [
        .items[]
        | select((.summary.fail // 0) > 0)
        | [(.results[]? | select(.result=="fail") | (.resources // [])[]?)]
        | select(length == 0)
      ] | length
    ' 2>/dev/null || echo "0")
    [[ -z "${pr_stale_count}" ]] && pr_stale_count=0

    if [[ -z "${pr_actionable_lines}" && -z "${cpr_fail_lines}" ]]; then
      if [[ "${pr_stale_count}" -gt 0 ]]; then
        ok "No actionable Kyverno PolicyReport failures detected (${pr_stale_count} stale audit record(s) ignored)"
      else
        ok "No Kyverno PolicyReport failures detected"
      fi
      return 0
    fi

    warn "Kyverno PolicyReport failures detected (audit findings):"
    if [[ -n "${pr_actionable_lines}" ]]; then
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        issue_count=$((issue_count + 1))
        if [[ "${issue_count}" -le 10 ]]; then
          warn "  ${line}"
        fi
      done <<<"${pr_actionable_lines}"
    fi
    if [[ -n "${cpr_fail_lines}" ]]; then
      while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        issue_count=$((issue_count + 1))
        if [[ "${issue_count}" -le 10 ]]; then
          warn "  cluster/${line}"
        fi
      done <<<"${cpr_fail_lines}"
    fi
    if [[ "${issue_count}" -gt 10 ]]; then
      warn "  ... and $((issue_count - 10)) more (run: kubectl get policyreport -A)"
    fi
    if [[ "${pr_stale_count}" -gt 0 ]]; then
      warn "  ${pr_stale_count} stale audit record(s) had no resource reference and were ignored"
    fi
    return 0
  fi

  if [[ -z "${pr_fail_lines}" && -z "${cpr_fail_lines}" ]]; then
    ok "No Kyverno PolicyReport failures detected"
    return 0
  fi

  warn "Kyverno PolicyReport failures detected (audit findings):"
  if [[ -n "${pr_fail_lines}" ]]; then
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      issue_count=$((issue_count + 1))
      if [[ "${issue_count}" -le 10 ]]; then
        warn "  ${line}"
      fi
    done <<<"${pr_fail_lines}"
  fi
  if [[ -n "${cpr_fail_lines}" ]]; then
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      issue_count=$((issue_count + 1))
      if [[ "${issue_count}" -le 10 ]]; then
        warn "  cluster/${line}"
      fi
    done <<<"${cpr_fail_lines}"
  fi
  if [[ "${issue_count}" -gt 10 ]]; then
    warn "  ... and $((issue_count - 10)) more (run: kubectl get policyreport -A)"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

HTTP_STATUS_LAST_MODE="direct"
KIND_GATEWAY_FALLBACK_WARNED=0

kind_gateway_url_probe_eligible() {
  local url="$1"
  local rest hostport host port

  [[ "${EXPECT_KIND_PROVISIONING}" == "true" ]] || return 1
  [[ "${url}" == https://* ]] || return 1

  rest="${url#https://}"
  hostport="${rest%%/*}"
  host="${hostport%%:*}"
  if [[ "${hostport}" == *:* ]]; then
    port="${hostport##*:}"
  else
    port="443"
  fi

  [[ "${port}" == "${GATEWAY_HTTPS_HOST_PORT}" ]] || return 1

  case "${host}" in
    "${PLATFORM_BASE_DOMAIN}"|*.${PLATFORM_BASE_DOMAIN}|"${PLATFORM_ADMIN_BASE_DOMAIN}"|*.${PLATFORM_ADMIN_BASE_DOMAIN})
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

kind_gateway_portforward_http_status_code() {
  local url="$1"
  local insecure="${2:-false}"
  local rest hostport path host local_port logfile pid code
  local -a port_candidates=(18443 19443 20443 21443)

  kind_gateway_url_probe_eligible "${url}" || return 1

  rest="${url#https://}"
  hostport="${rest%%/*}"
  if [[ "${rest}" == "${hostport}" ]]; then
    path="/"
  else
    path="/${rest#*/}"
  fi
  host="${hostport%%:*}"

  for local_port in "${port_candidates[@]}"; do
    logfile="$(mktemp)"
    kubectl -n platform-gateway port-forward svc/platform-gateway-nginx "${local_port}:443" >"${logfile}" 2>&1 &
    pid=$!

    for _ in $(seq 1 25); do
      if grep -q "Forwarding from" "${logfile}" 2>/dev/null; then
        break
      fi
      if ! kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done

    if ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${logfile}"
      continue
    fi

    if [[ "${insecure}" == "true" ]]; then
      code=$(curl -skI --max-time 5 -o /dev/null -w "%{http_code}" "https://${host}:${local_port}${path}" 2>/dev/null || true)
    else
      code=$(curl -sSI --max-time 5 -o /dev/null -w "%{http_code}" "https://${host}:${local_port}${path}" 2>/dev/null || true)
    fi
    [[ -n "${code}" ]] || code="000"

    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    rm -f "${logfile}"

    printf '%s\n' "${code}"
    return 0
  done

  return 1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

SHOW_URLS=0
TFVARS_FILES=()
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --var-file)
      if [[ -z "${2:-}" ]]; then
        shell_cli_missing_value "$(shell_cli_script_name)" "$1"
        exit 1
      fi
      TFVARS_FILES+=("${2:-}")
      shift 2
      ;;
    -u|--show-urls)
      SHOW_URLS=1
      shift
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would run stack-aware cluster health diagnostics"

require_cmd kubectl

platform_load_env

for i in "${!TFVARS_FILES[@]}"; do
  if [[ -n "${TFVARS_FILES[i]}" && ! -f "${TFVARS_FILES[i]}" && -f "${STACK_DIR}/${TFVARS_FILES[i]}" ]]; then
    TFVARS_FILES[i]="${STACK_DIR}/${TFVARS_FILES[i]}"
  fi
done

tfvar_get_in_file() {
  local file="$1"
  local key="$2"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo ""
    return 0
  fi
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true
}

tfvar_get() {
  local key="$1"
  local value=""
  local file current

  for file in "${TFVARS_FILES[@]}"; do
    current="$(tfvar_get_in_file "${file}" "${key}")"
    if [[ -n "${current}" ]]; then
      value="${current}"
    fi
  done

  echo "${value}"
}

tfvar_bool() {
  local key="$1"
  local v
  v=$(tfvar_get "$key")
  case "$v" in
    true|false) echo "$v" ;;
    *) echo "" ;;
  esac
}

tfvar_or_default() {
  local key="$1"
  local default="$2"
  local v
  v=$(tfvar_get "$key")
  if [[ -n "$v" ]]; then
    echo "$v"
  else
    echo "$default"
  fi
}

tfvar_list_entries() {
  local key="$1"
  local raw=""
  local file
  local entry=""
  local -a values=()

  for file in "${TFVARS_FILES[@]}"; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    raw="$(
      awk -v key="${key}" '
        !capture && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { capture=1 }
        capture { print }
        capture && /\]/ { exit }
      ' "${file}" 2>/dev/null || true
    )"
    [[ -n "${raw}" ]] || continue
    values=()
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      values+=("${entry}")
    done < <(printf '%s\n' "${raw}" | grep -oE '"[^"]+"' | sed 's/^"//;s/"$//' || true)
  done

  if [[ "${#values[@]}" -gt 0 ]]; then
    printf '%s\n' "${values[@]}"
  fi
}

detect_stage_from_tfvars() {
  local file base detected=""
  for file in "${TFVARS_FILES[@]}"; do
    [[ -n "${file}" ]] || continue
    base=$(basename "${file}")
    if [[ "${base}" =~ ^([0-9]{3})-.*\.tfvars$ ]]; then
      detected="${BASH_REMATCH[1]}"
    fi
  done

  echo "${detected}"
}

stage_ge() {
  local min_stage="$1"
  [[ -n "${CURRENT_STAGE}" && "${CURRENT_STAGE}" =~ ^[0-9]+$ && "${CURRENT_STAGE}" -ge "${min_stage}" ]]
}

section_active() {
  local min_stage="$1"
  local expected="$2"

  # When an explicit stage is supplied, stage gating wins over feature flags.
  # This keeps early-stage teaching runs from checking future-stage concerns.
  if [[ -n "${CURRENT_STAGE}" ]]; then
    stage_ge "${min_stage}"
    return
  fi

  if [[ "${expected}" == "true" ]]; then
    return 0
  fi

  return 0
}

expected_from_tfvars() {
  local key="$1"
  local v
  v=$(tfvar_bool "$key")
  if [[ "${#TFVARS_FILES[@]}" -eq 0 ]]; then
    echo "unknown"
  elif [[ -z "$v" ]]; then
    echo "unknown"
  else
    echo "$v"
  fi
}

expected_cilium_from_tfvars() {
  local v
  v=$(tfvar_get cni_provider)
  if [[ "${#TFVARS_FILES[@]}" -eq 0 || -z "$v" ]]; then
    echo "unknown"
  elif [[ "$v" == "cilium" ]]; then
    echo "true"
  elif [[ "$v" == "none" ]]; then
    echo "false"
  else
    echo "unknown"
  fi
}

EXPECT_CILIUM=$(expected_cilium_from_tfvars)
EXPECT_KIND_PROVISIONING=$(expected_from_tfvars provision_kind_cluster)
EXPECT_WIREGUARD=$(expected_from_tfvars enable_cilium_wireguard)
EXPECT_HUBBLE=$(expected_from_tfvars enable_hubble)
EXPECT_ARGOCD=$(expected_from_tfvars enable_argocd)
EXPECT_GITEA=$(expected_from_tfvars enable_gitea)
EXPECT_POLICIES=$(expected_from_tfvars enable_policies)
EXPECT_CILIUM_POLICIES=$(expected_from_tfvars enable_cilium_policies)
EXPECT_CILIUM_POLICY_AUDIT_MODE=$(expected_from_tfvars enable_cilium_policy_audit_mode)
EXPECT_SIGNOZ=$(expected_from_tfvars enable_signoz)
EXPECT_LOKI=$(expected_from_tfvars enable_loki)
EXPECT_VICTORIA_LOGS=$(expected_from_tfvars enable_victoria_logs)
EXPECT_TEMPO=$(expected_from_tfvars enable_tempo)
EXPECT_HEADLAMP=$(expected_from_tfvars enable_headlamp)
EXPECT_GATEWAY_TLS=$(expected_from_tfvars enable_gateway_tls)
EXPECT_SSO=$(expected_from_tfvars enable_sso)
SSO_PROVIDER=$(tfvar_get sso_provider)
[[ -n "${SSO_PROVIDER}" ]] || SSO_PROVIDER="keycloak"
EXPECT_PROMETHEUS=$(expected_from_tfvars enable_prometheus)
EXPECT_GRAFANA=$(expected_from_tfvars enable_grafana)
EXPECT_ACTIONS_RUNNER=$(expected_from_tfvars enable_actions_runner)
EXPECT_APP_REPO_SUBNET_CALC=$(expected_from_tfvars enable_app_repo_subnetcalc)
EXPECT_APP_REPO_SENTIMENT=$(expected_from_tfvars enable_app_repo_sentiment)
EXPECT_PREFER_EXTERNAL_WORKLOAD_IMAGES=$(expected_from_tfvars prefer_external_workload_images)
[[ -n "${EXPECT_CILIUM_POLICIES}" ]] || EXPECT_CILIUM_POLICIES="${EXPECT_POLICIES}"
[[ -n "${EXPECT_CILIUM_POLICY_AUDIT_MODE}" ]] || EXPECT_CILIUM_POLICY_AUDIT_MODE="false"
CURRENT_STAGE=$(detect_stage_from_tfvars)

ARGOCD_SERVER_NODE_PORT=$(tfvar_or_default argocd_server_node_port 30080)
HUBBLE_UI_NODE_PORT=$(tfvar_or_default hubble_ui_node_port 31235)
GITEA_HTTP_NODE_PORT=$(tfvar_or_default gitea_http_node_port 30090)
GITEA_SSH_NODE_PORT=$(tfvar_or_default gitea_ssh_node_port 30022)
SIGNOZ_UI_HOST_PORT=$(tfvar_or_default signoz_ui_host_port 3301)
GRAFANA_UI_HOST_PORT=$(tfvar_or_default grafana_ui_host_port 3302)
GATEWAY_HTTPS_HOST_PORT=$(tfvar_or_default gateway_https_host_port 443)
GITEA_SSH_USERNAME=$(tfvar_or_default gitea_ssh_username git)
GITEA_ADMIN_USERNAME=$(tfvar_or_default gitea_admin_username gitea-admin)
GITEA_REPO_OWNER=$(tfvar_or_default gitea_repo_owner "${GITEA_ADMIN_USERNAME}")
EXPECTED_CLUSTER_NAME=$(tfvar_or_default cluster_name kind-local)
PLATFORM_BASE_DOMAIN=$(tfvar_or_default platform_base_domain 127.0.0.1.sslip.io)
EXPOSE_ADMIN_NODEPORTS=$(tfvar_or_default expose_admin_nodeports true)
PLATFORM_ADMIN_BASE_DOMAIN=$(tfvar_get platform_admin_base_domain)
SEPARATE_ADMIN_DOMAIN=0
if [[ -n "${PLATFORM_ADMIN_BASE_DOMAIN}" ]]; then
  SEPARATE_ADMIN_DOMAIN=1
else
  PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN}"
fi
ADMIN_ROUTE_ALLOWLIST_ENABLED=0
if [[ -n "$(tfvar_list_entries admin_route_allowlist_cidrs)" ]]; then
  ADMIN_ROUTE_ALLOWLIST_ENABLED=1
fi
ADMIN_GATEWAY_EXPECTED_CODES="200 302 303"
if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" ]]; then
  ADMIN_GATEWAY_EXPECTED_CODES="${ADMIN_GATEWAY_EXPECTED_CODES} 403"
fi

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

keycloak_host() {
  printf 'keycloak.%s\n' "${PLATFORM_ADMIN_BASE_DOMAIN}"
}

GITEA_ADMIN_PWD_EFFECTIVE="${GITEA_ADMIN_PWD:-}"
if [[ -z "${GITEA_ADMIN_PWD_EFFECTIVE}" ]]; then
  pwd_from_tfvars=$(tfvar_get gitea_admin_pwd)
  if [[ -n "${pwd_from_tfvars}" ]]; then
    GITEA_ADMIN_PWD_EFFECTIVE="${pwd_from_tfvars}"
  elif [[ -n "${PLATFORM_ADMIN_PASSWORD:-}" ]]; then
    GITEA_ADMIN_PWD_EFFECTIVE="${PLATFORM_ADMIN_PASSWORD}"
  else
    GITEA_ADMIN_PWD_EFFECTIVE=""
  fi
fi
GITEA_ADMIN_AUTH_AVAILABLE=0
if [[ -n "${GITEA_ADMIN_PWD_EFFECTIVE}" ]]; then
  GITEA_ADMIN_AUTH_AVAILABLE=1
fi

ARGOCD_NS=$(tfvar_get argocd_namespace)
if [[ -z "${ARGOCD_NS}" ]]; then ARGOCD_NS="argocd"; fi

tfvars_hint=""
if [[ "${#TFVARS_FILES[@]}" -gt 0 ]]; then
  tfvars_hint=" in .tfvars input"
fi

if [[ -n "${CURRENT_STAGE}" ]]; then
  tfvars_hint="${tfvars_hint} (stage ${CURRENT_STAGE})"
fi

print_nodeport_urls() {
  local show_all="${1:-false}"
  echo "Port URLs (NodePort/host port):"
  if [[ "${EXPOSE_ADMIN_NODEPORTS}" != "true" ]]; then
    echo "  • Direct admin NodePorts disabled (expose_admin_nodeports=${EXPOSE_ADMIN_NODEPORTS})"
    return 0
  fi
  if [[ "${EXPECT_ARGOCD}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Argo CD:  http://127.0.0.1:${ARGOCD_SERVER_NODE_PORT}/"
  fi
  if [[ "${EXPECT_GITEA}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Gitea:    http://127.0.0.1:${GITEA_HTTP_NODE_PORT}/"
    echo "  • Gitea SSH: ssh://${GITEA_SSH_USERNAME}@127.0.0.1:${GITEA_SSH_NODE_PORT}"
  fi
  if [[ "${EXPECT_HUBBLE}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Hubble:   http://127.0.0.1:${HUBBLE_UI_NODE_PORT}/"
  fi
  if [[ "${EXPECT_SIGNOZ}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • SigNoz:   http://127.0.0.1:${SIGNOZ_UI_HOST_PORT}/"
  fi
  if [[ "${EXPECT_GRAFANA}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Grafana:  http://127.0.0.1:${GRAFANA_UI_HOST_PORT}/"
  fi
}

print_gateway_urls() {
  local show_all="${1:-false}"
  local port_suffix=""
  if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
    port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
  fi
  echo "HTTPS URLs (via NGINX Gateway Fabric):"
  echo "  • Public app zone: *.${PLATFORM_BASE_DOMAIN}"
  if [[ "${SEPARATE_ADMIN_DOMAIN}" == "1" ]]; then
    echo "  • Admin zone: *.${PLATFORM_ADMIN_BASE_DOMAIN}"
  fi
  echo "  • Argo CD:  https://$(admin_host argocd)${port_suffix}/"
  echo "  • Gitea:    https://$(admin_host gitea)${port_suffix}/"
  if [[ "${EXPECT_HUBBLE}" == "true" || ( "${show_all}" == "true" && "${EXPECT_HUBBLE}" != "false" ) ]]; then
    echo "  • Hubble:   https://$(admin_host hubble)${port_suffix}/"
  fi
  if [[ "${EXPECT_HEADLAMP}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Headlamp: https://$(admin_host headlamp)${port_suffix}/"
  fi
  if [[ "${EXPECT_SIGNOZ}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • SigNoz:   https://$(admin_host signoz)${port_suffix}/"
  fi
  if [[ "${EXPECT_GRAFANA}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Grafana:  https://$(admin_host grafana)${port_suffix}/"
  fi
  if [[ "${EXPECT_POLICIES}" == "true" || "${show_all}" == "true" ]]; then
    echo "  • Kyverno:  https://$(admin_host kyverno)${port_suffix}/"
  fi

  if [[ "${EXPECT_SSO}" == "true" ]]; then
    echo ""
    echo "SSO (${SSO_PROVIDER} + oauth2-proxy):"
    if [[ "${SSO_PROVIDER}" == "keycloak" ]]; then
      echo "  • Keycloak admin: https://$(keycloak_host)${port_suffix}/admin/platform/console/#/platform/users"
      echo "  • Keycloak realm: https://$(keycloak_host)${port_suffix}/realms/platform"
      echo "  • Console admin: demo@admin.test"
      echo "  • Break-glass admin: keycloak-admin"
    else
      echo "  • Dex:      https://$(dex_host)${port_suffix}/dex"
    fi
    echo "  • Users:    demo@admin.test, demo@dev.test, demo@uat.test"
    echo "  • Password: set via PLATFORM_DEMO_PASSWORD in .env"
  fi
  if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" ]]; then
    echo "  • Admin source allowlist active: non-allowlisted probes may receive HTTP 403"
  fi
}

check_http_surface() {
  local label="$1"
  local url="$2"
  local accepted_codes="$3"
  local insecure="${4:-false}"
  local timeout_seconds="${5:-0}"
  local retry_interval_seconds="${6:-5}"
  local code
  local deadline=0

  if ! have_cmd curl; then
    warn "${label} check skipped (curl not found)"
    return 0
  fi

  if [[ "${timeout_seconds}" -gt 0 ]]; then
    deadline=$((SECONDS + timeout_seconds))
  fi

  while :; do
    code="$(http_status_code "${url}" "${insecure}")"

    case " ${accepted_codes} " in
      *" ${code} "*)
        if [[ "${HTTP_STATUS_LAST_MODE}" == "kind-port-forward" && "${KIND_GATEWAY_FALLBACK_WARNED}" -eq 0 ]]; then
          warn "Direct kind HTTPS host publish on 127.0.0.1:${GATEWAY_HTTPS_HOST_PORT} did not respond; validating gateway URLs via kubectl port-forward fallback"
          KIND_GATEWAY_FALLBACK_WARNED=1
        fi
        ok "${label} reachable: ${url} (HTTP ${code})"
        return 0
        ;;
    esac

    if [[ "${timeout_seconds}" -le 0 || ${SECONDS} -ge ${deadline} ]]; then
      fail_soft "${label} not reachable: ${url} (HTTP ${code})"
      return 0
    fi

    sleep "${retry_interval_seconds}"
  done
}

first_node_internal_ip() {
  kubectl get nodes -o jsonpath='{range .items[*]}{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}{end}' 2>/dev/null | awk 'NF { print; exit }'
}

http_status_code() {
  local url="$1"
  local insecure="${2:-false}"
  local code=""

  HTTP_STATUS_LAST_MODE="direct"

  if [[ "${insecure}" == "true" ]]; then
    code=$(curl -skI --max-time 5 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || true)
  else
    code=$(curl -sSI --max-time 5 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || true)
  fi
  [[ -n "${code}" ]] || code="000"

  if [[ "${code}" == "000" ]]; then
    if code="$(kind_gateway_portforward_http_status_code "${url}" "${insecure}" 2>/dev/null)"; then
      HTTP_STATUS_LAST_MODE="kind-port-forward"
    else
      code="000"
    fi
  fi

  printf '%s\n' "${code}"
}

http_status_code_basic_auth() {
  local url="$1"
  local username="$2"
  local password="$3"

  curl -fsS --max-time 5 -o /dev/null -w "%{http_code}" -u "${username}:${password}" "${url}" 2>/dev/null || echo 000
}

check_nodeport_http_surface() {
  local label="$1"
  local port="$2"
  local path="${3:-/}"
  local accepted_codes="$4"
  local insecure="${5:-false}"
  local local_url="http://127.0.0.1:${port}${path}"
  local local_code node_ip node_url node_code

  if ! have_cmd curl; then
    warn "${label} check skipped (curl not found)"
    return 0
  fi

  local_code="$(http_status_code "${local_url}" "${insecure}")"
  case " ${accepted_codes} " in
    *" ${local_code} "*)
      ok "${label} reachable: ${local_url} (HTTP ${local_code})"
      return 0
      ;;
  esac

  node_ip="$(first_node_internal_ip)"
  if [[ -n "${node_ip}" && "${node_ip}" != "127.0.0.1" ]]; then
    node_url="http://${node_ip}:${port}${path}"
    node_code="$(http_status_code "${node_url}" "${insecure}")"
    case " ${accepted_codes} " in
      *" ${node_code} "*)
        ok "${label} reachable via node IP: ${node_url} (localhost unavailable: HTTP ${local_code})"
        return 0
        ;;
    esac
    fail_soft "${label} not reachable: ${local_url} (HTTP ${local_code}); node fallback ${node_url} (HTTP ${node_code})"
    return 0
  fi

  fail_soft "${label} not reachable: ${local_url} (HTTP ${local_code})"
}

check_gitea_api_surface() {
  local port="$1"
  local path="$2"
  local local_url="http://127.0.0.1:${port}${path}"
  local local_code node_ip node_url node_code

  if [[ "${GITEA_ADMIN_AUTH_AVAILABLE}" != "1" ]]; then
    warn "Skipping Gitea API auth checks; set PLATFORM_ADMIN_PASSWORD in .env or export GITEA_ADMIN_PWD"
    return 0
  fi

  if ! have_cmd curl; then
    warn "curl not found; skipping Gitea API reachability checks"
    return 0
  fi

  local_code="$(http_status_code_basic_auth "${local_url}" "${GITEA_ADMIN_USERNAME}" "${GITEA_ADMIN_PWD_EFFECTIVE}")"
  if [[ "${local_code}" == "200" ]]; then
    ok "Gitea API NodePort reachable: ${local_url}"
    return 0
  fi

  node_ip="$(first_node_internal_ip)"
  if [[ -n "${node_ip}" && "${node_ip}" != "127.0.0.1" ]]; then
    node_url="http://${node_ip}:${port}${path}"
    node_code="$(http_status_code_basic_auth "${node_url}" "${GITEA_ADMIN_USERNAME}" "${GITEA_ADMIN_PWD_EFFECTIVE}")"
    if [[ "${node_code}" == "200" ]]; then
      ok "Gitea API NodePort reachable via node IP: ${node_url} (localhost unavailable: HTTP ${local_code})"
      return 0
    fi
    warn "Gitea API NodePort not reachable on localhost:${port} or ${node_ip}:${port} (HTTP ${local_code}/${node_code}); repo/bootstrap automation will fail until one path is available"
    return 0
  fi

  warn "Gitea API NodePort not reachable on localhost:${port}; repo/bootstrap automation will fail until it is"
}

print_success_dashboard_hint() {
  local grafana_url=""

  if [[ "${EXPECT_GRAFANA}" != "true" || "${EXPECT_GATEWAY_TLS}" != "true" ]]; then
    return 0
  fi

  grafana_url="https://$(admin_host grafana)"
  if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
    grafana_url="${grafana_url}:${GATEWAY_HTTPS_HOST_PORT}"
  fi

  echo "Grafana launchpad: ${grafana_url}"
  if [[ "${EXPECT_SSO}" == "true" ]]; then
    echo "Users: demo@admin.test, demo@uat.test, demo@dev.test"
    echo "Password: set via PLATFORM_DEMO_PASSWORD in .env"
  fi
}

if [[ "${SHOW_URLS}" == "1" ]]; then
  print_nodeport_urls true
  echo ""
  print_gateway_urls true
  if [[ "${EXPECT_GATEWAY_TLS}" != "true" ]]; then
    echo ""
    echo "Note: enable_gateway_tls=${EXPECT_GATEWAY_TLS}${tfvars_hint}; HTTPS URLs require stage 800+."
  fi
  exit 0
fi

if [[ "${EXPECT_KIND_PROVISIONING}" == "true" ]]; then
  require_cmd kind
  require_cmd docker
  echo "Checking kind cluster..."
  if ! docker info >/dev/null 2>&1; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      fail "docker daemon not reachable (is Docker Desktop running?)"
    fi
    fail "docker daemon not reachable"
  fi
  if ! kind get clusters 2>/dev/null | grep -qx "${EXPECTED_CLUSTER_NAME}"; then
    fail "${EXPECTED_CLUSTER_NAME} cluster not found"
  fi
  ok "${EXPECTED_CLUSTER_NAME} cluster exists"
else
  echo "Checking Kubernetes cluster..."
  if [[ "${EXPECT_KIND_PROVISIONING}" == "false" ]]; then
    ok "Using existing kubeconfig-backed cluster (${EXPECTED_CLUSTER_NAME})"
  else
    warn "Cluster provisioning mode unknown${tfvars_hint}; using kubectl reachability"
  fi
fi

ctx=$(kubectl config current-context 2>/dev/null || true)
if [[ -z "${ctx}" ]]; then
  warn "kubectl current-context is empty; continuing"
else
  ok "kubectl context: ${ctx}"
fi

kubectl get nodes >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
ok "kubectl can reach the cluster"

if [[ -n "${CURRENT_STAGE}" ]]; then
  ok "Detected stage: ${CURRENT_STAGE}"
fi

echo ""
echo "Nodes:"
kubectl get nodes -o wide || true

not_ready_count="$(node_not_ready_count)"

if stage_ge 200 || [[ "${EXPECT_CILIUM}" == "true" ]]; then
  if [[ "${not_ready_count}" -gt 0 ]]; then
    warn "Waiting up to 60s for nodes to become Ready after CNI stage"
    if wait_for_all_nodes_ready 60; then
      ok "All nodes Ready"
    else
      fail_soft "Node readiness not OK (${not_ready_count} node(s) not Ready after CNI stage)"
    fi
  else
    ok "All nodes Ready"
  fi
else
  if [[ "${not_ready_count}" -gt 0 ]]; then
    ok "Node NotReady is tolerated before stage 200 installs CNI"
  else
    ok "All nodes Ready ahead of stage 200"
  fi
fi

echo ""
echo "Cilium (if installed):"
if ! section_active 200 "${EXPECT_CILIUM}"; then
  ok "Skipped until stage 200"
elif kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
  ok "Detected Cilium (cni_provider implies cilium=${EXPECT_CILIUM}${tfvars_hint})"
  kubectl -n kube-system get ds cilium
  kubectl -n kube-system get pods -l k8s-app=cilium -o wide || true
else
  if [[ "${EXPECT_CILIUM}" == "true" ]]; then
    fail_soft "Cilium not detected (cni_provider=cilium${tfvars_hint})"
  else
    ok "Cilium not detected (cni_provider implies cilium=${EXPECT_CILIUM}${tfvars_hint})"
  fi
fi

echo ""
echo "WireGuard encryption (if enabled):"
if ! section_active 200 "${EXPECT_CILIUM}"; then
  ok "Skipped until stage 200"
elif [[ "${EXPECT_WIREGUARD}" == "true" ]]; then
  wg_status=$(kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status 2>/dev/null | grep -i "Encryption" || true)
  if echo "${wg_status}" | grep -qi "wireguard"; then
    ok "Cilium WireGuard encryption active: ${wg_status}"
  else
    fail_soft "WireGuard not detected in Cilium status (enable_cilium_wireguard=true${tfvars_hint})"
  fi
else
  if [[ "${EXPECT_WIREGUARD}" == "false" ]]; then
    ok "WireGuard not enabled (enable_cilium_wireguard=false${tfvars_hint})"
  else
    ok "WireGuard status unknown (enable_cilium_wireguard not set${tfvars_hint})"
  fi
fi

echo ""
echo "Cilium policy audit mode (if enabled):"
if ! section_active 200 "${EXPECT_CILIUM}"; then
  ok "Skipped until stage 200"
elif [[ "${EXPECT_CILIUM_POLICY_AUDIT_MODE}" == "true" ]]; then
  audit_mode=$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.policy-audit-mode}' 2>/dev/null || true)
  if [[ "${audit_mode}" == "true" ]]; then
    ok "Cilium policy audit mode enabled"
  else
    fail_soft "Cilium policy audit mode not detected (enable_cilium_policy_audit_mode=true${tfvars_hint})"
  fi
else
  audit_mode=$(kubectl -n kube-system get configmap cilium-config -o jsonpath='{.data.policy-audit-mode}' 2>/dev/null || true)
  if [[ "${audit_mode}" == "true" ]]; then
    warn "Detected Cilium policy audit mode while enable_cilium_policy_audit_mode=${EXPECT_CILIUM_POLICY_AUDIT_MODE}${tfvars_hint}"
  else
    ok "Cilium policy audit mode disabled"
  fi
fi

echo ""
echo "Hubble (if installed):"
if ! section_active 300 "${EXPECT_HUBBLE}"; then
  ok "Skipped until stage 300"
else
  HUBBLE_SVC_PRESENT=0
  if kubectl -n kube-system get svc hubble-ui >/dev/null 2>&1; then
    HUBBLE_SVC_PRESENT=1
  fi

  if [[ "${HUBBLE_SVC_PRESENT}" -eq 1 ]]; then
    if [[ "${EXPECT_HUBBLE}" == "false" ]]; then
      warn "Detected Hubble UI but enable_hubble=false${tfvars_hint}"
    else
      ok "Detected Hubble UI (enable_hubble=${EXPECT_HUBBLE}${tfvars_hint})"
    fi

    kubectl -n kube-system get deploy hubble-relay hubble-ui 2>/dev/null || true
    kubectl -n kube-system get svc hubble-relay hubble-ui 2>/dev/null || true

    hubble_port=$(kubectl -n kube-system get svc hubble-ui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || true)
    if [[ -n "${hubble_port}" ]]; then
      ok "Hubble UI URL: http://localhost:${hubble_port}"
      check_nodeport_http_surface "Hubble UI direct URL" "${hubble_port}" "/" "200"
    fi
    if [[ "${EXPECT_GATEWAY_TLS}" == "true" && "${EXPECT_SSO}" == "true" ]]; then
      gateway_port_suffix=""
      if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
        gateway_port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
      fi
      check_http_surface "Hubble admin gateway URL" "https://$(admin_host hubble)${gateway_port_suffix}/" "${ADMIN_GATEWAY_EXPECTED_CODES}" true 30 5
    fi
  else
    if [[ "${EXPECT_HUBBLE}" == "true" ]]; then
      fail_soft "Hubble UI not detected (enable_hubble=true${tfvars_hint})"
    else
      ok "Hubble UI not detected (enable_hubble=${EXPECT_HUBBLE}${tfvars_hint})"
    fi
  fi
fi

echo ""
echo "Argo CD (if installed):"
if ! section_active 400 "${EXPECT_ARGOCD}"; then
  ok "Skipped until stage 400"
elif kubectl get ns "${ARGOCD_NS}" >/dev/null 2>&1; then
  ok "Detected Argo CD (enable_argocd=${EXPECT_ARGOCD}${tfvars_hint})"
  kubectl -n "${ARGOCD_NS}" get pods -o wide || true
  if kubectl -n "${ARGOCD_NS}" get svc argocd-server >/dev/null 2>&1; then
    kubectl -n "${ARGOCD_NS}" get svc argocd-server
  fi
  if [[ "${EXPOSE_ADMIN_NODEPORTS}" == "true" ]]; then
    check_nodeport_http_surface "Argo CD direct URL" "${ARGOCD_SERVER_NODE_PORT}" "/" "200"
  else
    ok "Argo CD direct NodePort disabled (expose_admin_nodeports=${EXPOSE_ADMIN_NODEPORTS})"
  fi
  if [[ "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
    gateway_port_suffix=""
    if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
      gateway_port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
    fi
    check_http_surface "Argo CD admin gateway URL" "https://$(admin_host argocd)${gateway_port_suffix}/" "${ADMIN_GATEWAY_EXPECTED_CODES}" true 30 5
  fi

  argocd_settle_timeout=60
  if stage_ge 800; then
    argocd_settle_timeout=180
  fi
  wait_for_argocd_apps_settled "${ARGOCD_NS}" "${argocd_settle_timeout}" || true

  echo ""
  echo "Argo CD Applications:"
  kubectl -n "${ARGOCD_NS}" get applications.argoproj.io 2>/dev/null || true

  check_all_argocd_apps "${ARGOCD_NS}"

  if kubectl -n "${ARGOCD_NS}" get app gitea >/dev/null 2>&1; then
    ok "Argo CD app gitea exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app signoz >/dev/null 2>&1; then
    ok "Argo CD app signoz exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app prometheus >/dev/null 2>&1; then
    ok "Argo CD app prometheus exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app loki >/dev/null 2>&1; then
    ok "Argo CD app loki exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app victoria-logs >/dev/null 2>&1; then
    ok "Argo CD app victoria-logs exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app tempo >/dev/null 2>&1; then
    ok "Argo CD app tempo exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app grafana >/dev/null 2>&1; then
    ok "Argo CD app grafana exists"
  fi
  if kubectl -n "${ARGOCD_NS}" get app headlamp >/dev/null 2>&1; then
    ok "Argo CD app headlamp exists"
  fi

  if [[ "${EXPECT_POLICIES}" == "true" ]]; then
    for app in kyverno kyverno-policies policy-reporter; do
      if kubectl -n "${ARGOCD_NS}" get app "${app}" >/dev/null 2>&1; then
        msg=$(kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)
        if [[ -n "${msg}" ]]; then
          warn "Argo CD app ${app} comparison error: ${msg}"
        fi
      else
        fail_soft "Argo CD app ${app} missing (enable_policies=true${tfvars_hint})"
      fi
    done

    if [[ "${EXPECT_CILIUM_POLICIES}" == "true" ]]; then
      if kubectl -n "${ARGOCD_NS}" get app cilium-policies >/dev/null 2>&1; then
        msg=$(kubectl -n "${ARGOCD_NS}" get app cilium-policies -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)
        if [[ -n "${msg}" ]]; then
          warn "Argo CD app cilium-policies comparison error: ${msg}"
        fi
      else
        fail_soft "Argo CD app cilium-policies missing (enable_cilium_policies=true${tfvars_hint})"
      fi
    else
      ok "Argo CD app cilium-policies intentionally disabled (enable_cilium_policies=${EXPECT_CILIUM_POLICIES}${tfvars_hint})"
    fi
  fi

  if [[ "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
    for app in cert-manager cert-manager-config nginx-gateway-fabric platform-gateway platform-gateway-routes; do
      if kubectl -n "${ARGOCD_NS}" get app "${app}" >/dev/null 2>&1; then
        msg=$(kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)
        if [[ -n "${msg}" ]]; then
          warn "Argo CD app ${app} comparison error: ${msg}"
        fi
      else
        fail_soft "Argo CD app ${app} missing (enable_gateway_tls=true${tfvars_hint})"
      fi
    done

    for crd in \
      gatewayclasses.gateway.networking.k8s.io \
      gateways.gateway.networking.k8s.io \
      httproutes.gateway.networking.k8s.io \
      nginxgateways.gateway.nginx.org \
      nginxproxies.gateway.nginx.org; do
      if kubectl get crd "${crd}" >/dev/null 2>&1; then
        established=$(kubectl get crd "${crd}" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null || true)
        if [[ "${established}" == "True" ]]; then
          ok "Gateway CRD ${crd} established"
        else
          fail_soft "Gateway CRD ${crd} not established"
        fi
      else
        fail_soft "Gateway CRD ${crd} missing (enable_gateway_tls=true${tfvars_hint})"
      fi
    done

    echo ""
    print_gateway_urls false
  fi

  if [[ "${EXPECT_SSO}" == "true" ]]; then
    sso_apps=(oauth2-proxy-argocd oauth2-proxy-gitea)
    if [[ "${SSO_PROVIDER}" == "keycloak" ]]; then
      if ! kubectl -n sso get deploy keycloak >/dev/null 2>&1; then
        fail_soft "Keycloak deployment missing (sso_provider=keycloak${tfvars_hint})"
      fi
      if ! kubectl -n sso get statefulset keycloak-postgres >/dev/null 2>&1; then
        fail_soft "Keycloak Postgres statefulset missing (sso_provider=keycloak${tfvars_hint})"
      fi
    else
      sso_apps+=(dex)
    fi
    if [[ "${EXPECT_HUBBLE}" == "true" ]]; then
      sso_apps+=(oauth2-proxy-hubble)
    fi
    if [[ "${EXPECT_GRAFANA}" == "true" ]]; then
      sso_apps+=(oauth2-proxy-grafana)
    fi
    if [[ "${EXPECT_SIGNOZ}" == "true" ]]; then
      sso_apps+=(oauth2-proxy-signoz)
    fi

    for app in "${sso_apps[@]}"; do
      if kubectl -n "${ARGOCD_NS}" get app "${app}" >/dev/null 2>&1; then
        msg=$(kubectl -n "${ARGOCD_NS}" get app "${app}" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)
        if [[ -n "${msg}" ]]; then
          warn "Argo CD app ${app} comparison error: ${msg}"
        fi
      else
        fail_soft "Argo CD app ${app} missing (enable_sso=true${tfvars_hint})"
      fi
    done
  fi

  if [[ "${EXPECT_APP_REPO_SUBNET_CALC}" == "true" ]]; then
    if kubectl -n "${ARGOCD_NS}" get app apim >/dev/null 2>&1; then
      ok "Argo CD app apim exists"
    else
      fail_soft "Argo CD app apim missing (enable_app_repo_subnetcalc=true${tfvars_hint})"
    fi
  fi

  if [[ "${EXPECT_APP_REPO_SENTIMENT}" == "true" || "${EXPECT_APP_REPO_SUBNET_CALC}" == "true" ]]; then
    for app in dev uat; do
      if kubectl -n "${ARGOCD_NS}" get app "${app}" >/dev/null 2>&1; then
        ok "Argo CD app ${app} exists"
      else
        fail_soft "Argo CD app ${app} missing (workload repos enabled${tfvars_hint})"
      fi
    done
  fi
else
  if [[ "${EXPECT_ARGOCD}" == "true" ]]; then
    fail_soft "Argo CD namespace not found (enable_argocd=true${tfvars_hint})"
  else
    ok "Argo CD not detected (enable_argocd=${EXPECT_ARGOCD}${tfvars_hint})"
  fi
fi

echo ""
echo "Gitea (if installed):"
if ! section_active 500 "${EXPECT_GITEA}"; then
  ok "Skipped until stage 500"
elif kubectl get ns gitea >/dev/null 2>&1; then
  ok "Detected Gitea namespace (enable_gitea=${EXPECT_GITEA}${tfvars_hint})"
  kubectl -n gitea get pods -o wide || true
  kubectl -n gitea get svc || true

  if have_cmd curl; then
    if [[ "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
      gateway_port_suffix=""
      [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]] && gateway_port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
      check_http_surface "Gitea HTTPS gateway" "https://$(admin_host gitea)${gateway_port_suffix}/" "${ADMIN_GATEWAY_EXPECTED_CODES}" true 30 5
    fi

    if [[ "${EXPOSE_ADMIN_NODEPORTS}" == "true" ]]; then
      check_gitea_api_surface "${GITEA_HTTP_NODE_PORT}" "/api/v1/version"
    else
      ok "Gitea direct NodePort disabled (expose_admin_nodeports=${EXPOSE_ADMIN_NODEPORTS})"
    fi
  else
    warn "curl not found; skipping Gitea gateway and API reachability checks"
  fi

  if [[ "${EXPECT_POLICIES}" == "true" || "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
    if kubectl -n "${ARGOCD_NS}" get secret repo-gitea-policies >/dev/null 2>&1; then
      ok "Argo CD repo secret exists: ${ARGOCD_NS}/repo-gitea-policies"
    else
      fail_soft "Argo CD repo secret missing: ${ARGOCD_NS}/repo-gitea-policies (policies/gateway GitOps will not sync)"
    fi
  fi
else
  if [[ "${EXPECT_GITEA}" == "true" ]]; then
    fail_soft "Gitea namespace not found (enable_gitea=true${tfvars_hint})"
  else
    ok "Gitea not detected (enable_gitea=${EXPECT_GITEA}${tfvars_hint})"
  fi
fi

echo ""
echo "Apps / pipelines (Gitea repos) (if enabled):"
if ! section_active 700 "${EXPECT_APP_REPO_SUBNET_CALC}" && ! section_active 700 "${EXPECT_APP_REPO_SENTIMENT}" && ! section_active 700 "${EXPECT_ACTIONS_RUNNER}"; then
  ok "Skipped until stage 700"
else
gitea_repo_check() {
  local repo="$1"
  local wf_path="$2"
  local expected="$3"

  if [[ "${expected}" != "true" ]]; then
    ok "${repo}: not enabled (enable=${expected}${tfvars_hint})"
    return 0
  fi

  if ! have_cmd curl; then
    fail_soft "${repo}: curl not found; cannot check Gitea repo"
    return 0
  fi

  if [[ "${EXPECT_GITEA}" != "true" ]]; then
    fail_soft "${repo}: expected enabled but enable_gitea=${EXPECT_GITEA}${tfvars_hint}"
    return 0
  fi

  if [[ "${GITEA_ADMIN_AUTH_AVAILABLE}" != "1" ]]; then
    warn "${repo}: skipping authenticated Gitea checks; set PLATFORM_ADMIN_PASSWORD in .env or export GITEA_ADMIN_PWD"
    return 0
  fi

  if [[ "${EXPECT_ACTIONS_RUNNER}" != "true" && "${EXPECT_PREFER_EXTERNAL_WORKLOAD_IMAGES}" == "true" ]]; then
    ok "${repo}: repo sync skipped (external images + runner disabled${tfvars_hint})"
    return 0
  fi

  local base="http://127.0.0.1:${GITEA_HTTP_NODE_PORT}"
  local code

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD_EFFECTIVE}" \
    "${base}/api/v1/repos/${GITEA_REPO_OWNER}/${repo}" \
    2>/dev/null || echo 000)

  if [[ "${code}" == "200" ]]; then
    ok "${repo}: repo present in Gitea (${GITEA_REPO_OWNER}/${repo})"
  else
    if [[ "${code}" == "401" || "${code}" == "403" ]]; then
      fail_soft "${repo}: repo check unauthorized (HTTP ${code}). Set GITEA_ADMIN_PWD or PLATFORM_ADMIN_PASSWORD before running this script."
    else
      fail_soft "${repo}: repo missing/unreachable (HTTP ${code})"
    fi
    return 0
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD_EFFECTIVE}" \
    "${base}/api/v1/repos/${GITEA_REPO_OWNER}/${repo}/contents/${wf_path}?ref=main" \
    2>/dev/null || echo 000)

  if [[ "${code}" == "200" ]]; then
    ok "${repo}: workflow present (${wf_path})"
  else
    if [[ "${code}" == "401" || "${code}" == "403" ]]; then
      fail_soft "${repo}: workflow check unauthorized (HTTP ${code})"
    else
      fail_soft "${repo}: workflow missing (${wf_path}) (HTTP ${code})"
    fi
  fi
}

gitea_repo_check "subnetcalc" ".gitea/workflows/build-images.yaml" "${EXPECT_APP_REPO_SUBNET_CALC}"
gitea_repo_check "sentiment" ".gitea/workflows/build-images.yaml" "${EXPECT_APP_REPO_SENTIMENT}"
fi

echo ""
echo "Gitea Actions runner (if enabled):"
if ! section_active 700 "${EXPECT_ACTIONS_RUNNER}"; then
  ok "Skipped until stage 700"
elif [[ "${EXPECT_ACTIONS_RUNNER}" == "true" ]]; then
  if kubectl get ns gitea-runner >/dev/null 2>&1; then
    if kubectl -n gitea-runner get deploy act-runner >/dev/null 2>&1; then
      ok "Detected runner deployment: gitea-runner/act-runner"
      kubectl -n gitea-runner get pods -o wide || true
    else
      fail_soft "Runner deployment missing: gitea-runner/act-runner (enable_actions_runner=true${tfvars_hint})"
    fi
  else
    fail_soft "Runner namespace missing: gitea-runner (enable_actions_runner=true${tfvars_hint})"
  fi
else
  ok "Runner not enabled (enable_actions_runner=${EXPECT_ACTIONS_RUNNER}${tfvars_hint})"
fi

echo ""
echo "Observability (SigNoz/Prometheus/Grafana/Loki/VictoriaLogs/Tempo):"
if ! section_active 800 "${EXPECT_SIGNOZ}" && ! section_active 800 "${EXPECT_PROMETHEUS}" && ! section_active 800 "${EXPECT_GRAFANA}" && ! section_active 800 "${EXPECT_LOKI}" && ! section_active 800 "${EXPECT_VICTORIA_LOGS}" && ! section_active 800 "${EXPECT_TEMPO}"; then
  ok "Skipped until stage 800"
elif kubectl get ns observability >/dev/null 2>&1; then
  ok "Detected observability namespace"
  kubectl -n observability get pods -o wide || true
  echo ""

  # SigNoz
  if kubectl -n observability get svc signoz-ui >/dev/null 2>&1; then
    ok "SigNoz detected (enable_signoz=${EXPECT_SIGNOZ}${tfvars_hint})"
    kubectl -n observability get svc signoz-ui || true
  else
    if [[ "${EXPECT_SIGNOZ}" == "true" ]]; then
      fail_soft "SigNoz not detected (enable_signoz=true${tfvars_hint})"
    else
      ok "SigNoz not detected (enable_signoz=${EXPECT_SIGNOZ}${tfvars_hint})"
    fi
  fi

  # Prometheus
  if kubectl -n observability get svc prometheus-server >/dev/null 2>&1; then
    ok "Prometheus detected (enable_prometheus=${EXPECT_PROMETHEUS}${tfvars_hint})"
    kubectl -n observability get svc prometheus-server || true
  else
    if [[ "${EXPECT_PROMETHEUS}" == "true" ]]; then
      fail_soft "Prometheus not detected (enable_prometheus=true${tfvars_hint})"
    else
      ok "Prometheus not detected (enable_prometheus=${EXPECT_PROMETHEUS}${tfvars_hint})"
    fi
  fi

  # Grafana
  if kubectl -n observability get svc grafana >/dev/null 2>&1; then
    ok "Grafana detected (enable_grafana=${EXPECT_GRAFANA}${tfvars_hint})"
    kubectl -n observability get svc grafana || true
    if [[ "${EXPECT_GATEWAY_TLS}" == "true" && "${EXPECT_SSO}" == "true" ]]; then
      gateway_port_suffix=""
      if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
        gateway_port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
      fi
      check_http_surface "Grafana admin gateway URL" "https://$(admin_host grafana)${gateway_port_suffix}/" "${ADMIN_GATEWAY_EXPECTED_CODES}" true 30 5
    fi
  else
    if [[ "${EXPECT_GRAFANA}" == "true" ]]; then
      fail_soft "Grafana not detected (enable_grafana=true${tfvars_hint})"
    else
      ok "Grafana not detected (enable_grafana=${EXPECT_GRAFANA}${tfvars_hint})"
    fi
  fi

  # Loki
  if kubectl -n observability get svc loki >/dev/null 2>&1; then
    ok "Loki detected (enable_loki=${EXPECT_LOKI}${tfvars_hint})"
    kubectl -n observability get svc loki || true
  else
    if [[ "${EXPECT_LOKI}" == "true" ]]; then
      fail_soft "Loki not detected (enable_loki=true${tfvars_hint})"
    else
      ok "Loki not detected (enable_loki=${EXPECT_LOKI}${tfvars_hint})"
    fi
  fi

  # VictoriaLogs
  if kubectl -n observability get svc victoria-logs-victoria-logs-single-server >/dev/null 2>&1; then
    ok "VictoriaLogs detected (enable_victoria_logs=${EXPECT_VICTORIA_LOGS}${tfvars_hint})"
    kubectl -n observability get svc victoria-logs-victoria-logs-single-server || true
  else
    if [[ "${EXPECT_VICTORIA_LOGS}" == "true" ]]; then
      fail_soft "VictoriaLogs not detected (enable_victoria_logs=true${tfvars_hint})"
    else
      ok "VictoriaLogs not detected (enable_victoria_logs=${EXPECT_VICTORIA_LOGS}${tfvars_hint})"
    fi
  fi

  # Tempo
  if kubectl -n observability get svc tempo >/dev/null 2>&1; then
    ok "Tempo detected (enable_tempo=${EXPECT_TEMPO}${tfvars_hint})"
    kubectl -n observability get svc tempo || true
  else
    if [[ "${EXPECT_TEMPO}" == "true" ]]; then
      fail_soft "Tempo not detected (enable_tempo=true${tfvars_hint})"
    else
      ok "Tempo not detected (enable_tempo=${EXPECT_TEMPO}${tfvars_hint})"
    fi
  fi

  # OTel Collector
  if kubectl -n observability get svc otel-collector >/dev/null 2>&1; then
    ok "OTel Collector detected"
    kubectl -n observability get svc otel-collector || true
  fi

  if [[ "${EXPECT_PROMETHEUS}" == "true" || "${EXPECT_GRAFANA}" == "true" ]]; then
    if kubectl -n observability get deploy -l app.kubernetes.io/name=kube-state-metrics --no-headers 2>/dev/null | grep -q .; then
      if kubectl -n observability rollout status deploy/prometheus-kube-state-metrics --timeout=180s >/dev/null 2>&1; then
        ok "kube-state-metrics ready for Grafana launchpad and Kubernetes readiness dashboards"
      else
        fail_soft "kube-state-metrics deployment is not Ready; Grafana launchpad tiles backed by kube_* metrics may stay Down"
      fi
    else
      fail_soft "kube-state-metrics missing; Grafana launchpad tiles backed by kube_* metrics will stay Down"
    fi

    if kubectl -n observability get daemonset -l app.kubernetes.io/name=prometheus-node-exporter --no-headers 2>/dev/null | grep -q .; then
      ok "node-exporter present for Grafana node dashboards"
    else
      fail_soft "node-exporter missing; Grafana node dashboards will be empty"
    fi
  fi
else
  if [[ "${EXPECT_SIGNOZ}" == "true" || "${EXPECT_PROMETHEUS}" == "true" || "${EXPECT_GRAFANA}" == "true" || "${EXPECT_LOKI}" == "true" || "${EXPECT_VICTORIA_LOGS}" == "true" || "${EXPECT_TEMPO}" == "true" ]]; then
    fail_soft "observability namespace not found (observability components enabled${tfvars_hint})"
  else
    ok "Observability namespace not detected"
  fi
fi

echo ""
echo "Headlamp (if installed):"
if ! section_active 800 "${EXPECT_HEADLAMP}"; then
  ok "Skipped until stage 800"
elif kubectl get ns headlamp >/dev/null 2>&1; then
  ok "Detected headlamp namespace (enable_headlamp=${EXPECT_HEADLAMP}${tfvars_hint})"
  kubectl -n headlamp get pods -o wide || true
  if kubectl -n headlamp get svc headlamp >/dev/null 2>&1; then
    kubectl -n headlamp get svc headlamp || true
    if [[ "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
      gateway_port_suffix=""
      if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
        gateway_port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
      fi
      check_http_surface "Headlamp admin gateway URL" "https://$(admin_host headlamp)${gateway_port_suffix}/" "${ADMIN_GATEWAY_EXPECTED_CODES}" true 30 5
    fi
  fi
  if [[ "${EXPECT_GATEWAY_TLS}" == "true" && "${EXPECT_POLICIES}" == "true" ]]; then
    gateway_port_suffix=""
    if [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]]; then
      gateway_port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"
    fi
    check_http_surface "Kyverno admin gateway URL" "https://$(admin_host kyverno)${gateway_port_suffix}/" "${ADMIN_GATEWAY_EXPECTED_CODES}" true 30 5
  fi
else
  if [[ "${EXPECT_HEADLAMP}" == "true" ]]; then
    fail_soft "headlamp namespace not found (enable_headlamp=true${tfvars_hint})"
  else
    ok "Headlamp not detected (enable_headlamp=${EXPECT_HEADLAMP}${tfvars_hint})"
  fi
fi

summarize_policy_posture

if [[ "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
  echo ""
  echo "Gateway/TLS (if installed):"
  if kubectl get ns platform-gateway >/dev/null 2>&1; then
    if kubectl -n platform-gateway get gateway platform-gateway >/dev/null 2>&1; then
      ok "Detected Gateway: platform-gateway/platform-gateway"
      kubectl -n platform-gateway get gateway platform-gateway || true
    else
      fail_soft "Gateway missing: platform-gateway/platform-gateway (enable_gateway_tls=true${tfvars_hint})"
    fi

    if kubectl -n platform-gateway get secret platform-gateway-tls >/dev/null 2>&1; then
      ok "TLS secret present: platform-gateway/platform-gateway-tls"
    else
      fail_soft "TLS secret missing: platform-gateway/platform-gateway-tls (cert-manager/mkcert may still be reconciling)"
    fi

    if kubectl -n platform-gateway get secret platform-gateway-nginx-agent-tls >/dev/null 2>&1; then
      ok "Agent TLS secret present: platform-gateway/platform-gateway-nginx-agent-tls"
    else
      fail_soft "Agent TLS secret missing: platform-gateway/platform-gateway-nginx-agent-tls (bootstrap runs during terraform apply)"
    fi
  else
    fail_soft "platform-gateway namespace missing (enable_gateway_tls=true${tfvars_hint})"
  fi
elif ! section_active 800 "${EXPECT_GATEWAY_TLS}"; then
  echo ""
  echo "Gateway/TLS (if installed):"
  ok "Skipped until stage 800"
fi

echo ""
if [[ "${FAILURES}" -gt 0 ]]; then
  fail "Health check failed (${FAILURES} issue(s))"
fi

ok "Health check completed"
print_success_dashboard_hint
