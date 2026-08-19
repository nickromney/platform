#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wait-for-gitea-ssh.sh"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Hard-refresh repo-backed Argo CD applications and wait until comparison
state is stable. Managed-workloads-ready is a soft wait condition.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would hard-refresh repo-backed Argo CD applications" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${ARGOCD_NS:?ARGOCD_NS is required}"
: "${APP_NAMES?APP_NAMES must be set}"
: "${ROLLOUT_SHORT_SECONDS:?ROLLOUT_SHORT_SECONDS is required}"
: "${ROLLOUT_TIMEOUT_SECONDS:?ROLLOUT_TIMEOUT_SECONDS is required}"
: "${GITEA_SSH_TIMEOUT_SECONDS:?GITEA_SSH_TIMEOUT_SECONDS is required}"
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found in PATH" >&2; exit 1; }

WAIT_FOR_GITEA_SSH_MODE="${WAIT_FOR_GITEA_SSH_MODE:-best-effort}"

if [[ -z "$APP_NAMES" ]]; then
  exit 0
fi

if ! kubectl -n "$ARGOCD_NS" get deployment argocd-repo-server >/dev/null 2>&1; then
  echo "WARN argocd-repo-server deployment not found in namespace $ARGOCD_NS; skipping refresh" >&2
  exit 0
fi

kubectl -n "$ARGOCD_NS" rollout status deployment argocd-repo-server --timeout="${ROLLOUT_SHORT_SECONDS}s" >/dev/null 2>&1 || true
if kubectl -n "$ARGOCD_NS" get statefulset argocd-application-controller >/dev/null 2>&1; then
  kubectl -n "$ARGOCD_NS" rollout status statefulset argocd-application-controller --timeout="${ROLLOUT_SHORT_SECONDS}s" >/dev/null 2>&1 || true
fi

wait_for_gitea_ssh

app_list="$(printf '%s' "$APP_NAMES" | tr ',' '\n')"

refresh_app() {
  local app="$1"
  kubectl -n "$ARGOCD_NS" annotate app "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
}

get_resource_jsonpath() {
  local resource_kind="$1"
  local resource_namespace="$2"
  local resource_name="$3"
  local jsonpath_expr="$4"

  if [[ -n "$resource_namespace" ]]; then
    kubectl -n "$resource_namespace" get "$resource_kind" "$resource_name" -o "jsonpath=$jsonpath_expr" 2>/dev/null || true
  else
    kubectl get "$resource_kind" "$resource_name" -o "jsonpath=$jsonpath_expr" 2>/dev/null || true
  fi
}

managed_workloads_ready() {
  local app="$1"
  local workloads=""
  local found_workload=0

  workloads="$(kubectl -n "$ARGOCD_NS" get app "$app" -o json 2>/dev/null | jq -r '
    .status.resources[]?
    | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")
    | [(.kind // ""), (.namespace // ""), (.name // "")]
    | @tsv
  ' 2>/dev/null || true)"

  while IFS=$'\t' read -r workload_kind workload_namespace workload_name; do
    local desired=""
    local ready=""
    local complete=""

    [[ -n "$workload_kind" && -n "$workload_name" ]] || continue
    found_workload=1

    case "$workload_kind" in
      Deployment)
        desired="$(get_resource_jsonpath deployment "$workload_namespace" "$workload_name" '{.spec.replicas}')"
        ready="$(get_resource_jsonpath deployment "$workload_namespace" "$workload_name" '{.status.readyReplicas}')"
        ;;
      StatefulSet)
        desired="$(get_resource_jsonpath statefulset "$workload_namespace" "$workload_name" '{.spec.replicas}')"
        ready="$(get_resource_jsonpath statefulset "$workload_namespace" "$workload_name" '{.status.readyReplicas}')"
        ;;
      DaemonSet)
        desired="$(get_resource_jsonpath daemonset "$workload_namespace" "$workload_name" '{.status.desiredNumberScheduled}')"
        ready="$(get_resource_jsonpath daemonset "$workload_namespace" "$workload_name" '{.status.numberReady}')"
        ;;
      Job)
        complete="$(get_resource_jsonpath job "$workload_namespace" "$workload_name" '{.status.conditions[?(@.type=="Complete")].status}')"
        [[ "$complete" == "True" ]] || return 1
        continue
        ;;
      *)
        continue
        ;;
    esac

    if [[ -z "$desired" ]]; then
      desired="1"
    fi
    if [[ -z "$ready" ]]; then
      ready="0"
    fi

    [[ "$ready" -ge "$desired" ]] || return 1
  done <<< "$workloads"

  [[ "$found_workload" -eq 1 ]]
}

needs_refresh_reason=""
needs_refresh() {
  local app="$1"
  local sync_status
  local health_status
  local comparison_msg

  needs_refresh_reason=""

  sync_status="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health_status="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  comparison_msg="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)"

  if grep -qiE 'knownhosts: key is unknown|failed to list refs: dial tcp .*:22: connect: connection refused|failed to list refs: unexpected EOF' <<<"$comparison_msg"; then
    needs_refresh_reason="comparison=$comparison_msg"
    return 0
  fi

  # Argo can keep the parent Application at Unknown/Degraded/Progressing after
  # the child resources have all become ready. Only treat that as stale cache
  # when the live managed workloads are actually ready; some Argo versions leave
  # child resource sync/health empty while the workloads are still converging.
  if [[ "$sync_status" == "Unknown" && -z "$comparison_msg" ]] && managed_workloads_ready "$app"; then
    needs_refresh_reason="managed-workloads-ready"
    return 0
  fi

  if [[ "$sync_status" == "Synced" && "$health_status" != "Healthy" ]] && managed_workloads_ready "$app"; then
    needs_refresh_reason="managed-workloads-ready"
    return 0
  fi

  if [[ "$sync_status" == "Unknown" ]]; then
    needs_refresh_reason="sync=Unknown"
    return 0
  fi

  return 1
}

while IFS= read -r app; do
  [[ -n "$app" ]] || continue
  if kubectl -n "$ARGOCD_NS" get app "$app" >/dev/null 2>&1; then
    refresh_app "$app"
  fi
done <<< "$app_list"

# Give the controller time to process the initial hard-refresh wave before
# deciding whether any app is still stale.
sleep 15

end=$((SECONDS + ROLLOUT_TIMEOUT_SECONDS))
stable_passes=0
soft_only_stable_passes=0
last_pending_summary=""
last_hard_pending_summary=""
last_soft_pending_summary=""
while (( SECONDS < end )); do
  pending=0
  pending_apps=()
  hard_pending_apps=()
  soft_pending_apps=()
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if ! kubectl -n "$ARGOCD_NS" get app "$app" >/dev/null 2>&1; then
      continue
    fi

    if needs_refresh "$app"; then
      pending=1
      pending_apps+=("$app:$needs_refresh_reason")
      if [[ "$needs_refresh_reason" == "managed-workloads-ready" ]]; then
        # Once the initial hard-refresh wave has landed, a Synced app with live
        # workloads ready usually just needs the controller to settle its parent
        # health. Re-refreshing every few seconds can keep the app looking
        # perpetually unsettled. Treat this as a soft wait condition instead.
        soft_pending_apps+=("$app:$needs_refresh_reason")
      else
        refresh_app "$app"
        hard_pending_apps+=("$app:$needs_refresh_reason")
      fi
    fi
  done <<< "$app_list"

  if [[ "$pending" -eq 0 ]]; then
    stable_passes=$((stable_passes + 1))
    soft_only_stable_passes=0
    last_pending_summary=""
    last_hard_pending_summary=""
    last_soft_pending_summary=""
    if [[ "$stable_passes" -ge 2 ]]; then
      exit 0
    fi
  else
    stable_passes=0
    last_pending_summary="${pending_apps[*]-}"
    last_hard_pending_summary="${hard_pending_apps[*]-}"
    last_soft_pending_summary="${soft_pending_apps[*]-}"
    if [[ "${#hard_pending_apps[@]}" -eq 0 && "${#soft_pending_apps[@]}" -gt 0 ]]; then
      soft_only_stable_passes=$((soft_only_stable_passes + 1))
      if [[ "$soft_only_stable_passes" -ge 2 ]]; then
        echo "WARN repo-backed Argo CD applications were still waiting on parent health after refresh, but no repo comparison errors remained: $last_soft_pending_summary" >&2
        exit 0
      fi
    else
      soft_only_stable_passes=0
    fi
  fi

  sleep 5
done

if [[ -n "$last_hard_pending_summary" ]]; then
  echo "Repo-backed Argo CD applications still have stale comparison state after refresh: $last_hard_pending_summary" >&2
  exit 1
fi

if [[ -n "$last_soft_pending_summary" ]]; then
  echo "WARN repo-backed Argo CD applications were still waiting on parent health after refresh, but no repo comparison errors remained: $last_soft_pending_summary" >&2
  exit 0
fi

if [[ -n "$last_pending_summary" ]]; then
  echo "Repo-backed Argo CD applications still have stale comparison state after refresh: $last_pending_summary" >&2
else
  echo "Repo-backed Argo CD applications still have stale comparison state after refresh" >&2
fi
exit 1