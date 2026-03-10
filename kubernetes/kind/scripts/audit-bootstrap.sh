#!/usr/bin/env bash
set -euo pipefail

ok() { printf 'OK   %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

EVENT_LOOKBACK_MINUTES="${EVENT_LOOKBACK_MINUTES:-15}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

show_previous_logs() {
  local ns="$1"
  local name="$2"
  local container="${4:-}"
  local label="${ns}/pod/${name}"
  local cmd=(kubectl -n "${ns}" logs "pod/${name}" --previous --tail=120)

  if [[ -n "${container}" ]]; then
    cmd+=( -c "${container}" )
    label="${label}:${container}"
  fi

  if "${cmd[@]}" >/tmp/audit-bootstrap.log 2>&1; then
    warn "Previous logs found for ${label}"
    sed -n '1,120p' /tmp/audit-bootstrap.log
    echo ""
  fi
}

require_cmd kubectl
require_cmd jq

kubectl get ns >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"

pods_json="$(kubectl get pods -A -o json)"

echo "== Context =="
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ -n "${ctx}" ]]; then
  ok "kubectl current-context=${ctx}"
else
  warn "kubectl current-context is empty"
fi
kubectl get nodes -o wide

echo ""
echo "== Argo CD Apps =="
if kubectl -n argocd get applications.argoproj.io >/dev/null 2>&1; then
  kubectl -n argocd get applications.argoproj.io
  for app in cert-manager cert-manager-config nginx-gateway-fabric platform-gateway platform-gateway-routes kyverno kyverno-policies cilium-policies gitea gitea-actions-runner apim dev uat dex oauth2-proxy-argocd oauth2-proxy-gitea oauth2-proxy-grafana oauth2-proxy-hubble oauth2-proxy-sentiment-dev oauth2-proxy-sentiment-uat oauth2-proxy-subnetcalc-dev oauth2-proxy-subnetcalc-uat prometheus grafana loki headlamp; do
    if ! kubectl -n argocd get app "${app}" >/dev/null 2>&1; then
      warn "Argo CD app missing: ${app}"
    fi
  done
else
  warn "Argo CD namespace/applications not present"
fi

echo ""
echo "== Pods =="
kubectl get pods -A -o wide

echo ""
echo "== Non-Running Pods =="
non_running="$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4 != "Running" && $4 != "Completed" {print}')"
if [[ -n "${non_running}" ]]; then
  warn "Found non-running pods"
  printf '%s\n' "${non_running}"
else
  ok "All pods are Running or Completed"
fi

echo ""
echo "== Pods With Non-Ready Containers =="
not_ready="$(
  printf '%s\n' "${pods_json}" | jq -r '
    .items[]
    | .metadata.namespace as $ns
    | .metadata.name as $pod
    | ((.status.initContainerStatuses // []) + (.status.containerStatuses // [])) as $statuses
    | [ $statuses[]? | select((.ready // true) != true) | .name ] as $not_ready
    | select(($not_ready | length) > 0)
    | "\($ns)\t\($pod)\tcontainers=\($not_ready | join(","))\tphase=\(.status.phase // "Unknown")"
  '
)"
if [[ -n "${not_ready}" ]]; then
  warn "Found pods with non-ready containers"
  printf '%s\n' "${not_ready}"
else
  ok "All pod containers are Ready"
fi

echo ""
echo "== Restart Audit =="
restart_lines="$(
  printf '%s\n' "${pods_json}" | jq -r '
    .items[]
    | .metadata.namespace as $ns
    | .metadata.name as $pod
    | ((.status.initContainerStatuses // []) + (.status.containerStatuses // []))[]
    | select((.restartCount // 0) > 0)
    | "\($ns)\t\($pod)\t\(.name)\trestarts=\(.restartCount)"
  '
)"
if [[ -n "${restart_lines}" ]]; then
  warn "Pods with restarts detected"
  printf '%s\n' "${restart_lines}"
else
  ok "No pod restarts detected"
fi

echo ""
echo "== Gateway / TLS =="
kubectl get gateway,httproute,certificate -A 2>/dev/null || true

echo ""
echo "== Recent Warning Events =="
events_json="$(kubectl get events -A -o json 2>/dev/null || true)"
recent_warning_events="$(
  printf '%s\n' "${events_json}" | jq -r --argjson lookback_seconds "$((EVENT_LOOKBACK_MINUTES * 60))" '
    [
      .items[]?
      | select(.type == "Warning")
      | (.eventTime // .lastTimestamp // .series.lastObservedTime // .metadata.creationTimestamp) as $ts
      | select(($ts | fromdateiso8601?) >= (now - $lookback_seconds))
      | [
          (.metadata.namespace // "-"),
          ($ts // "-"),
          (.reason // "-"),
          ((.involvedObject.kind // "-") + "/" + (.involvedObject.name // "-")),
          (.message // "" | gsub("[\r\n\t]+"; " "))
        ]
      | @tsv
    ][]
  '
)"
older_warning_count="$(
  printf '%s\n' "${events_json}" | jq -r --argjson lookback_seconds "$((EVENT_LOOKBACK_MINUTES * 60))" '
    [
      .items[]?
      | select(.type == "Warning")
      | (.eventTime // .lastTimestamp // .series.lastObservedTime // .metadata.creationTimestamp) as $ts
      | select(($ts | fromdateiso8601?) < (now - $lookback_seconds))
    ] | length
  '
)"
if [[ -n "${recent_warning_events}" ]]; then
  warn "Warning events in the last ${EVENT_LOOKBACK_MINUTES} minute(s)"
  printf 'NAMESPACE\tTIMESTAMP\tREASON\tOBJECT\tMESSAGE\n'
  printf '%s\n' "${recent_warning_events}"
else
  ok "No warning events in the last ${EVENT_LOOKBACK_MINUTES} minute(s)"
  if [[ "${older_warning_count}" != "0" ]]; then
    warn "Older bootstrap warning events still exist (${older_warning_count})"
  fi
fi

echo ""
echo "== Policy Reports =="
kubectl get policyreport,clusterpolicyreport -A 2>/dev/null || true

echo ""
echo "== Previous Container Logs =="
previous_log_targets="$(
  printf '%s\n' "${pods_json}" | jq -r '
    .items[]
    | .metadata.namespace as $ns
    | .metadata.name as $pod
    | ((.status.initContainerStatuses // []) + (.status.containerStatuses // []))[]
    | select((.restartCount // 0) > 0)
    | "\($ns)\t\($pod)\t\(.name)"
  '
)"

if [[ -z "${previous_log_targets}" ]]; then
  ok "No restarted containers, so no previous logs to inspect"
else
  while IFS=$'\t' read -r ns pod container; do
    [[ -z "${ns}" || -z "${pod}" || -z "${container}" ]] && continue
    show_previous_logs "${ns}" "${pod}" "${container}"
  done <<< "${previous_log_targets}"
fi
