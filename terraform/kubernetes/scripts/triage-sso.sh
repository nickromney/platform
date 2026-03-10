#!/usr/bin/env bash
set -euo pipefail

section() {
  echo
  echo "==> $*"
}

have() { command -v "$1" >/dev/null 2>&1; }

require() {
  if ! have "$1"; then
    echo "Missing required binary: $1" >&2
    exit 1
  fi
}

require kubectl

PYTHON_BIN=""
if have python3; then
  PYTHON_BIN="python3"
elif have python; then
  PYTHON_BIN="python"
else
  echo "Missing python3/python (needed to parse JSON arg arrays from kubectl jsonpath)" >&2
  exit 1
fi

print_oauth2_proxy_args() {
  local deploy="$1"
  local ns="${2:-sso}"

  local args_json
  args_json="$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{.spec.template.spec.containers[0].args}')"

  echo "Deployment: ${ns}/${deploy}"
  # jsonpath prints a JSON array; parse and print selected flags for readability.
  printf '%s' "${args_json}" | "${PYTHON_BIN}" -c '
import json, sys
args = json.loads(sys.stdin.read() or "[]")
keys = [
  "--cookie-name",
  "--cookie-domain",
  "--email-domain",
  "--redirect-url",
  "--upstream",
  "--skip-auth-regex",
  "--set-authorization-header",
  "--pass-access-token",
  "--set-xauthrequest",
  "--pass-user-headers",
  "--login-url",
  "--oidc-issuer-url",
]
for a in args:
  if any(k in a for k in keys):
    print("  " + a)
'
}

curl_in_cluster() {
  # Keep this read-only and avoid dumping response bodies that might contain tokens.
  local name="$1"
  local ns="${2:-default}"
  shift
  shift || true
  kubectl -n "${ns}" run "${name}" --rm -i --restart=Never --image=curlimages/curl:8.7.1 -- \
    sh -lc "$*"
}

section "Cluster / Namespaces"
kubectl get ns

section "Gateway Routes (hostnames -> backend)"
kubectl -n gateway-routes get httproute -o wide
echo
kubectl -n gateway-routes get httproute -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.hostnames[*]}{.}{","}{end}{"\t"}{range .spec.rules[*].backendRefs[*]}{.namespace}{"/"}{.name}{":"}{.port}{","}{end}{"\n"}{end}' \
  | sed 's/,$//' || true

section "oauth2-proxy Deployments (key args)"
kubectl -n sso get deploy -o name | grep -E 'deployment.apps/oauth2-proxy-' | sed 's|deployment.apps/||' | while read -r dep; do
  print_oauth2_proxy_args "${dep}" "sso"
done

section "ArgoCD Applications: oauth2-proxy helm parameter overrides"
kubectl -n argocd get application -o name | grep -E 'application.argoproj.io/oauth2-proxy-' | sed 's|application.argoproj.io/||' | while read -r app; do
  params="$(kubectl -n argocd get application "${app}" -o jsonpath='{.spec.source.helm.parameters}' 2>/dev/null || true)"
  if [[ -n "${params}" && "${params}" != "[]" ]]; then
    echo "app=${app} parameters=${params}"
  fi
done

section "Signoz auth-bridge smoke checks (avoid printing tokens)"
kubectl -n observability get deploy signoz-auth-proxy >/dev/null 2>&1 && {
  curl_in_cluster curlsignozprecheck default \
    "set -euo pipefail; \
     echo '-- signoz-auth-proxy /api/v1/loginPrecheck'; \
     curl -sS --max-time 10 -o /dev/null -D - http://signoz-auth-proxy.observability.svc.cluster.local:3000/api/v1/loginPrecheck | sed -n '1,15p'; \
     echo; \
     echo '-- signoz-auth-proxy /api/v1/version'; \
     curl -sS --max-time 10 -o /dev/null -D - http://signoz-auth-proxy.observability.svc.cluster.local:3000/api/v1/version | sed -n '1,15p'"
} || echo "observability/signoz-auth-proxy deployment not found; skipping."

section "Sentiment LLM smoke checks (dev/uat) - latency + llama.cpp model readiness"
# These checks bypass oauth2-proxy (auth) and measure pure upstream performance, which is useful when
# oauth2-proxy returns a 502 due to upstream timeouts.
for ns in sentiment-dev uat; do
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    echo "-- namespace ${ns} not found; skipping"
    continue
  fi

  echo "-- ${ns}: router health (expect 200)"
  curl_in_cluster "curlsent-${ns//[^a-z0-9]/}" "${ns}" \
    "set -euo pipefail; \
     curl -sS --max-time 5 -o /dev/null -w 'status=%{http_code} time=%{time_total}s\n' \
       http://sentiment-router.${ns}.svc.cluster.local:8080/api/v1/health || true; \
     echo; \
     echo '-- ${ns}: llama.cpp /v1/models (expect 200)'; \
     curl -sS --max-time 5 -o /dev/null -w 'status=%{http_code} time=%{time_total}s\n' \
       http://llama.${ns}.svc.cluster.local:8080/v1/models || true; \
     echo; \
     echo '-- ${ns}: analyze (POST /api/v1/comments) - should be interactive (seconds, not minutes)'; \
     curl -sS --max-time 15 -o /dev/null -w 'status=%{http_code} time=%{time_total}s\n' \
       -H 'Content-Type: application/json' -d '{\"text\":\"hello\"}' \
       http://sentiment-router.${ns}.svc.cluster.local:8080/api/v1/comments || true"
done

section "Local HTTPS smoke checks (optional; uses 127.0.0.1:443)"
if have curl; then
  for host in \
    gitea.admin.127.0.0.1.sslip.io \
    argocd.admin.127.0.0.1.sslip.io \
    signoz.admin.127.0.0.1.sslip.io \
    kyverno.admin.127.0.0.1.sslip.io \
    subnetcalc.uat.127.0.0.1.sslip.io \
  ; do
    echo "-- ${host} / (expect 302 to dex when unauthenticated)"
    curl -skI --max-time 5 --resolve "${host}:443:127.0.0.1" "https://${host}/" | sed -n '1,12p' || true
    echo
  done
else
  echo "curl not found; skipping local HTTPS checks."
fi

section "Done"
echo "If something is off, cross-check:"
echo "- HTTPRoute backendRefs"
echo "- oauth2-proxy --upstream / --redirect-url / cookie-domain"
echo "- ArgoCD Application helm.parameters overriding helm.values"
