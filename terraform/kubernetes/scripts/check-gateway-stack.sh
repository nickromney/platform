#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

# Repeatable diagnostics for "gateway stack is broken" situations:
# - No pods in platform-gateway
# - HTTPRoutes missing
# - cert-manager components crashlooping
# - In-cluster service connectivity issues (e.g. pods can't reach kubernetes.default)
#
# Intended to be safe to run anytime; best-effort output, no mutations.

FAILURES=0
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage:
  check-gateway-stack.sh [options]

Options:
  --since DURATION     Log window (default: 20m)
  --tail N            Log tail lines (default: 200)
  --strict            Exit non-zero if any failures detected (default)
  --no-strict         Always exit 0 (for ad-hoc debugging)

EOF
  printf '%s\n' "$(shell_cli_standard_options)"
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL $1 not found in PATH" >&2; exit 1; }; }

SINCE="20m"
TAIL="200"
STRICT=1

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --tail) TAIL="${2:-}"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --no-strict) STRICT=0; shift ;;
    *) echo "FAIL Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would run gateway stack diagnostics"

require kubectl

section() {
  echo
  echo "== $*"
}

run() {
  # Run a command and keep its stdout/stderr. Never abort the script.
  # Usage: run kubectl ...
  set +e
  "$@"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    warn "command failed (rc=${rc}): $*"
  fi
  return 0
}

argocd_app_exists() {
  kubectl -n argocd get app "$1" >/dev/null 2>&1
}

print_argocd_app() {
  local app="$1"
  if ! argocd_app_exists "${app}"; then
    fail_soft "Argo CD app argocd/${app} not found"
    return 0
  fi
  local sync health msg
  sync="$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  msg="$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.operationState.message}' 2>/dev/null || true)"
  echo "app=${app} sync=${sync:-?} health=${health:-?}"
  if [[ -n "${msg}" && "${msg}" != "null" ]]; then
    echo "  opMessage=${msg}"
  fi
  if [[ "${health}" != "Healthy" || "${sync}" != "Synced" ]]; then
    fail_soft "Argo CD app ${app} not Synced/Healthy (sync=${sync:-?} health=${health:-?})"
    echo "  non-Healthy resources (kind ns/name sync health msg):"
    kubectl -n argocd get app "${app}" -o jsonpath='{range .status.resources[?(@.health.status!="Healthy")]}{.kind}{" "}{.namespace}{"/"}{.name}{" sync="}{.status}{" health="}{.health.status}{" msg="}{.health.message}{"\n"}{end}' 2>/dev/null | head -n 30 || true
  fi
}

detect_argocd_gitops_mode() {
  if argocd_app_exists "app-of-apps"; then
    printf '%s\n' "app-of-apps"
    return 0
  fi

  printf '%s\n' "direct"
}

print_endpointslices_for_service() {
  local ns="$1"
  local svc="$2"
  if ! kubectl -n "${ns}" get svc "${svc}" >/dev/null 2>&1; then
    return 0
  fi
  kubectl -n "${ns}" get endpointslices -l "kubernetes.io/service-name=${svc}" -o wide 2>/dev/null || true
}

tail_deploy_logs() {
  local ns="$1"
  local deploy="$2"
  local container="${3:-}"
  if ! kubectl -n "${ns}" get deploy "${deploy}" >/dev/null 2>&1; then
    return 0
  fi
  echo
  echo "Logs tail: ${ns}/deploy/${deploy} (since=${SINCE})"
  if [[ -n "${container}" ]]; then
    run kubectl -n "${ns}" logs deploy/"${deploy}" -c "${container}" --since="${SINCE}" --tail="${TAIL}"
  else
    run kubectl -n "${ns}" logs deploy/"${deploy}" --since="${SINCE}" --tail="${TAIL}"
  fi
}

tail_pod_logs() {
  local ns="$1"
  local pod="$2"
  local previous="${3:-0}"
  local args=(kubectl -n "${ns}" logs "${pod}" --since="${SINCE}" --tail="${TAIL}")
  if [[ "${previous}" == "1" ]]; then
    args=(kubectl -n "${ns}" logs "${pod}" --previous --tail="${TAIL}")
  fi
  run "${args[@]}"
}

section "Context"
ctx="$(kubectl config current-context 2>/dev/null || true)"
if [[ -n "${ctx}" ]]; then
  ok "kubectl context=${ctx}"
else
  fail_soft "kubectl current-context empty"
fi
run kubectl version --client
run kubectl get nodes -o wide
run kubectl get ns | head -n 30

section "Argo CD Apps (core)"
gitops_mode="$(detect_argocd_gitops_mode)"
case "${gitops_mode}" in
  app-of-apps)
    ok "Detected Argo CD app-of-apps mode"
    apps=(
      app-of-apps
      cert-manager
      cert-manager-config
      cilium-policies
      kyverno
      kyverno-policies
      nginx-gateway-fabric
      platform-gateway
      platform-gateway-routes
    )
    ;;
  direct)
    ok "Detected direct Argo CD mode (no app-of-apps parent)"
    apps=(
      cert-manager
      cert-manager-config
      cilium-policies
      kyverno
      kyverno-policies
      nginx-gateway-fabric
      platform-gateway
      platform-gateway-routes
    )
    ;;
esac
for a in "${apps[@]}"; do
  print_argocd_app "${a}"
done

echo
echo "All Argo CD Applications (if CRD present):"
run kubectl -n argocd get app -o wide

section "Gateway CRDs"
gateway_crds=(
  gatewayclasses.gateway.networking.k8s.io
  gateways.gateway.networking.k8s.io
  httproutes.gateway.networking.k8s.io
  nginxgateways.gateway.nginx.org
  nginxproxies.gateway.nginx.org
)
for crd in "${gateway_crds[@]}"; do
  run kubectl get crd "${crd}" -o 'custom-columns=NAME:.metadata.name,ESTABLISHED:.status.conditions[?(@.type=="Established")].status'
done

section "CNI / Service Networking (quick signals)"
echo "kubernetes service:"
run kubectl -n default get svc kubernetes -o wide
echo "kubernetes endpointslices:"
run kubectl -n default get endpointslices -l kubernetes.io/service-name=kubernetes -o wide

echo
echo "cilium pods (best-effort):"
if kubectl get ns cilium >/dev/null 2>&1; then
  run kubectl -n cilium get pods -o wide
fi
run kubectl -n kube-system get pods -o wide
echo
echo "cilium/kube-proxy subset:"
run kubectl -n kube-system get pods -o wide | grep -E '(^NAME|cilium|kube-proxy)' || true

section "cert-manager"
run kubectl -n cert-manager get pods -o wide
if kubectl -n cert-manager get pods -l app=cainjector >/dev/null 2>&1; then
  bad="$(kubectl -n cert-manager get pods -l app=cainjector -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.containerStatuses[0].ready}{" "}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' 2>/dev/null || true)"
  if echo "${bad}" | grep -q " false "; then
    fail_soft "cert-manager cainjector not Ready"
    pod="$(kubectl -n cert-manager get pods -l app=cainjector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "${pod}" ]]; then
      echo
      echo "describe pod: cert-manager/${pod}"
      run kubectl -n cert-manager describe pod "${pod}" | sed -n '1,220p'
      echo
      echo "logs (previous): cert-manager/${pod}"
      tail_pod_logs cert-manager "${pod}" 1
      echo
      echo "logs (current): cert-manager/${pod}"
      tail_pod_logs cert-manager "${pod}" 0
    fi
  else
    ok "cert-manager cainjector Ready"
  fi
fi

section "SigNoz Bootstrap (platform-gateway-routes hook)"
run kubectl -n observability get svc signoz -o wide
run kubectl -n observability get svc signoz-clickhouse -o wide
run kubectl -n observability get pods -o wide | grep -E '(^NAME|signoz|clickhouse|schema-migrator|bootstrap)' || true
if kubectl -n observability get job signoz-bootstrap >/dev/null 2>&1; then
  run kubectl -n observability get job signoz-bootstrap -o wide
  echo
  echo "signoz-bootstrap logs (tail):"
  run kubectl -n observability logs job/signoz-bootstrap --tail=80
fi

section "Gateway API Objects"
echo "Gateways:"
run kubectl get gateway -A -o wide
echo
echo "HTTPRoutes:"
run kubectl get httproute -A -o wide

section "Gateway Namespaces"
for ns in platform-gateway nginx-gateway gateway-system; do
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    continue
  fi
  echo "-- namespace: ${ns} --"
  run kubectl -n "${ns}" get pods -o wide
  run kubectl -n "${ns}" get deploy,svc -o wide
  if kubectl -n "${ns}" get svc platform-gateway-nginx-internal >/dev/null 2>&1; then
    echo "endpointslices (${ns}/platform-gateway-nginx-internal):"
    print_endpointslices_for_service "${ns}" platform-gateway-nginx-internal
  fi
done

section "Gateway Controller Logs (best-effort)"
tail_deploy_logs nginx-gateway nginx-gateway-fabric
tail_deploy_logs platform-gateway platform-gateway-nginx nginx

section "Argo CD repo-server (if unhealthy)"
run kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server -o wide
tail_deploy_logs argocd argocd-repo-server

if [[ "${FAILURES}" -gt 0 ]]; then
  warn "Failures: ${FAILURES}"
  if [[ "${STRICT}" -eq 1 ]]; then
    exit 1
  fi
else
  ok "No failures detected"
fi
