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

# --- Per-pass cluster snapshots ---------------------------------------------
#
# Each predicate below used to issue its own kubectl read per application and
# per managed workload, so one stability pass over this stack's ~45 repo-backed
# applications cost hundreds of serial API round trips. Measured on this repo's
# kind cluster: 129 serial per-app reads took 62.2s, against 1.29s for one
# `kubectl -n argocd get app -o json` list and 0.31s for one cluster-wide
# workload list. Every pass now takes exactly those two reads.
APP_SNAPSHOT_FILE="$(mktemp "${TMPDIR:-/tmp}/argocd-apps.XXXXXX")"
WORKLOAD_SNAPSHOT_FILE="$(mktemp "${TMPDIR:-/tmp}/argocd-workloads.XXXXXX")"
trap 'rm -f "$APP_SNAPSHOT_FILE" "$WORKLOAD_SNAPSHOT_FILE" "$APP_SNAPSHOT_FILE.pending" "$WORKLOAD_SNAPSHOT_FILE.pending" "$APP_SNAPSHOT_FILE.names"' EXIT

snapshot_file() {
  local target="$1"
  shift

  if kubectl "$@" -o json >"${target}.pending" 2>/dev/null; then
    mv -f "${target}.pending" "${target}"
  else
    rm -f "${target}.pending"
    printf '{"items":[]}\n' >"${target}"
  fi
}

# Refreshes both snapshots. Callers do this once at the top of every pass, so
# no predicate ever reads data older than its own pass.
refresh_snapshots() {
  snapshot_file "$APP_SNAPSHOT_FILE" -n "$ARGOCD_NS" get applications.argoproj.io
  snapshot_file "$WORKLOAD_SNAPSHOT_FILE" get deployments,statefulsets,daemonsets,jobs -A
  # Name index, so the per-app existence check costs a grep rather than a jq process.
  jq -r '.items[]?.metadata.name // empty' "$APP_SNAPSHOT_FILE" 2>/dev/null \
    | sort >"$APP_SNAPSHOT_FILE.names" || : >"$APP_SNAPSHOT_FILE.names"
}

app_query() {
  local app="$1"
  local filter="$2"

  jq -r --arg app "$app" ".items[]? | select(.metadata.name == \$app) | ${filter}" \
    "$APP_SNAPSHOT_FILE" 2>/dev/null || true
}

app_exists() {
  local app="$1"

  grep -Fxq -- "$app" "$APP_SNAPSHOT_FILE.names" 2>/dev/null
}

# Prints "desired<TAB>ready" for one managed workload, empty when it is absent.
# Jobs report desired=1 and ready=1 only when the Complete condition is True,
# which is the same test the per-Job jsonpath read used to make.
workload_state() {
  local workload_kind="$1"
  local workload_namespace="$2"
  local workload_name="$3"

  jq -r \
    --arg kind "$workload_kind" \
    --arg ns "$workload_namespace" \
    --arg name "$workload_name" '
      .items[]?
      | select(.kind == $kind and .metadata.name == $name and .metadata.namespace == $ns)
      | if .kind == "DaemonSet" then
          [(.status.desiredNumberScheduled // ""), (.status.numberReady // "")]
        elif .kind == "Job" then
          [1, (if any(.status.conditions[]?; .type == "Complete" and .status == "True") then 1 else 0 end)]
        else
          [(.spec.replicas // ""), (.status.readyReplicas // "")]
        end
      | @tsv
    ' "$WORKLOAD_SNAPSHOT_FILE" 2>/dev/null | head -n 1 || true
}

managed_workloads_ready() {
  local app="$1"
  local workloads=""
  local found_workload=0

  workloads="$(app_query "$app" '
    .status.resources[]?
    | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")
    | [(.kind // ""), (.namespace // ""), (.name // "")]
    | @tsv
  ')"

  while IFS=$'\t' read -r workload_kind workload_namespace workload_name; do
    local state=""
    local desired=""
    local ready=""

    [[ -n "$workload_kind" && -n "$workload_name" ]] || continue
    found_workload=1

    case "$workload_kind" in
      Deployment | StatefulSet | DaemonSet | Job) ;;
      *) continue ;;
    esac

    state="$(workload_state "$workload_kind" "$workload_namespace" "$workload_name")"
    IFS=$'\t' read -r desired ready <<< "$state" || true

    # An absent workload reads as desired=1 ready=0, matching the old behaviour
    # where a failed per-resource lookup returned empty strings.
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

  sync_status="$(app_query "$app" '.status.sync.status // ""')"
  health_status="$(app_query "$app" '.status.health.status // ""')"
  comparison_msg="$(app_query "$app" '[.status.conditions[]? | select(.type == "ComparisonError") | .message // ""] | join("")')"

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

REFRESH_WAVE_TIMEOUT_SECONDS="${REFRESH_WAVE_TIMEOUT_SECONDS:-15}"
REFRESH_WAVE_POLL_SECONDS="${REFRESH_WAVE_POLL_SECONDS:-1}"

# True while any app in the wave still carries an unprocessed refresh request.
# The application controller strips argocd.argoproj.io/refresh once it has
# handled the refresh, so this is the observable form of "the wave has landed".
refresh_wave_pending() {
  local app pending

  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    pending="$(app_query "$app" '.metadata.annotations["argocd.argoproj.io/refresh"] // ""')"
    [[ -z "$pending" ]] || return 0
  done <<< "$app_list"

  return 1
}

refresh_snapshots

while IFS= read -r app; do
  [[ -n "$app" ]] || continue
  if app_exists "$app"; then
    refresh_app "$app"
  fi
done <<< "$app_list"

# Wait for the controller to consume the initial hard-refresh wave before
# deciding whether any app is still stale. This replaces a flat 15s sleep: the
# budget is the same, but a controller that processes the wave in a second no
# longer costs the other fourteen.
wave_end=$((SECONDS + REFRESH_WAVE_TIMEOUT_SECONDS))
while (( SECONDS < wave_end )); do
  refresh_snapshots
  refresh_wave_pending || break
  sleep "$REFRESH_WAVE_POLL_SECONDS"
done

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
  # One Application list and one workload list per pass; every predicate below
  # reads those instead of issuing its own per-app and per-workload queries.
  refresh_snapshots
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if ! app_exists "$app"; then
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