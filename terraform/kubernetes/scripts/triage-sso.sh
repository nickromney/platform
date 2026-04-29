#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

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

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Prints a read-only SSO triage bundle for gateway routes, oauth2-proxy
deployments, Argo CD applications, and in-cluster curl probes.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would print the SSO triage diagnostics bundle" "$@"

require kubectl

PLATFORM_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_ADMIN_BASE_DOMAIN:-${PLATFORM_BASE_DOMAIN}}"
SSO_PROVIDER="${SSO_PROVIDER:-keycloak}"
DEVCONTAINER_HOST_ALIAS="${PLATFORM_DEVCONTAINER_HOST_ALIAS:-${KIND_DEVCONTAINER_HOST_ALIAS:-host.docker.internal}}"
SEPARATE_ADMIN_DOMAIN=0
if [[ "${PLATFORM_ADMIN_BASE_DOMAIN}" != "${PLATFORM_BASE_DOMAIN}" ]]; then
  SEPARATE_ADMIN_DOMAIN=1
fi

admin_host() {
  local app="$1"
  if [[ "${SEPARATE_ADMIN_DOMAIN}" == "1" ]]; then
    printf '%s.%s\n' "${app}" "${PLATFORM_ADMIN_BASE_DOMAIN}"
  else
    printf '%s.admin.%s\n' "${app}" "${PLATFORM_BASE_DOMAIN}"
  fi
}

oauth2_proxy_arg_of_interest() {
  case "$1" in
    --cookie-name*|--cookie-domain*|--email-domain*|--allowed-group*|--oidc-groups-claim*|--redirect-url*|--upstream*|--skip-auth-regex*|--set-authorization-header*|--pass-access-token*|--set-xauthrequest*|--pass-user-headers*|--login-url*|--oidc-issuer-url*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

devcontainer_enabled() {
  [[ "${PLATFORM_DEVCONTAINER:-0}" == "1" ]]
}

print_oauth2_proxy_args() {
  local deploy="$1"
  local ns="${2:-sso}"

  local args_lines
  args_lines="$(kubectl -n "${ns}" get deploy "${deploy}" -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' 2>/dev/null || true)"
  [[ -n "${args_lines}" ]] || return 0

  echo "Deployment: ${ns}/${deploy}"
  while IFS= read -r arg; do
    [[ -n "${arg}" ]] || continue
    if oauth2_proxy_arg_of_interest "${arg}"; then
      printf '  %s\n' "${arg}"
    fi
  done <<< "${args_lines}"
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
if kubectl -n observability get deploy signoz-auth-proxy >/dev/null 2>&1; then
  curl_in_cluster curlsignozprecheck default \
    "set -euo pipefail; \
     echo '-- signoz-auth-proxy /api/v1/loginPrecheck'; \
     curl -sS --max-time 10 -o /dev/null -D - http://signoz-auth-proxy.observability.svc.cluster.local:3000/api/v1/loginPrecheck | sed -n '1,15p'; \
     echo; \
     echo '-- signoz-auth-proxy /api/v1/version'; \
     curl -sS --max-time 10 -o /dev/null -D - http://signoz-auth-proxy.observability.svc.cluster.local:3000/api/v1/version | sed -n '1,15p'"
else
  echo "observability/signoz-auth-proxy deployment not found; optional SigNoz path is inactive."
fi

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

section "Local HTTPS smoke checks (optional; uses 127.0.0.1:443 or the devcontainer host alias)"
if have curl; then
  hosts=(
    "$(admin_host gitea)"
    "$(admin_host argocd)"
    "$(admin_host kyverno)"
    "subnetcalc.uat.${PLATFORM_BASE_DOMAIN}"
  )
  if kubectl -n observability get deploy signoz >/dev/null 2>&1 || kubectl -n observability get deploy signoz-auth-proxy >/dev/null 2>&1; then
    hosts+=("$(admin_host signoz)")
  fi

  for host in "${hosts[@]}"; do
    echo "-- ${host} / (expect 302 to ${SSO_PROVIDER} when unauthenticated)"
    if devcontainer_enabled; then
      curl -skI --max-time 5 --connect-to "${host}:443:${DEVCONTAINER_HOST_ALIAS}:443" "https://${host}/" | sed -n '1,12p' || true
    else
      curl -skI --max-time 5 --resolve "${host}:443:127.0.0.1" "https://${host}/" | sed -n '1,12p' || true
    fi
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
