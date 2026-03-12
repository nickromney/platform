#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

FAILURES=0
fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }
fail_soft() { echo "${RED}✖${NC} $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "${YELLOW}⚠${NC} $*"; }
ok() { echo "${GREEN}✔${NC} $*"; }
skip() { echo "${YELLOW}⊘${NC} $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmd kubectl

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

TFVARS_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file) TFVARS_FILE="${2:-}"; shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [[ -n "${TFVARS_FILE}" && ! -f "${TFVARS_FILE}" ]]; then
  if [[ -f "${STACK_DIR}/${TFVARS_FILE}" ]]; then
    TFVARS_FILE="${STACK_DIR}/${TFVARS_FILE}"
  fi
fi

tfvar_get() {
  local file="$1" key="$2"
  [[ -z "${file}" || ! -f "${file}" ]] && { echo ""; return 0; }
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true
}

tfvar_bool() {
  local v; v=$(tfvar_get "$1" "$2")
  case "$v" in true|false) echo "$v" ;; *) echo "" ;; esac
}

expected_platform_gateway_tls_directives() {
  awk '
    /^[[:space:]]*value: \|$/ { in_value=1; next }
    in_value {
      if ($0 ~ /^  [^ ]/) {
        exit
      }
      line=$0
      sub(/^        /, "", line)
      if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) {
        next
      }
      print line
    }
  ' "${STACK_DIR}/apps/platform-gateway/tls-hardening.yaml"
}

live_platform_gateway_nginx_conf() {
  kubectl -n platform-gateway exec deploy/platform-gateway-nginx -- \
    sh -c 'find /etc/nginx -type f ! -path "*/secrets/*" -exec cat {} + 2>/dev/null' 2>/dev/null || true
}

EXPECT_WIREGUARD=$(tfvar_bool "${TFVARS_FILE}" enable_cilium_wireguard)
EXPECT_GATEWAY_TLS=$(tfvar_bool "${TFVARS_FILE}" enable_gateway_tls)
EXPECT_POLICIES=$(tfvar_bool "${TFVARS_FILE}" enable_policies)
GATEWAY_HTTPS_HOST_PORT=$(tfvar_get "${TFVARS_FILE}" gateway_https_host_port)
[[ -z "${GATEWAY_HTTPS_HOST_PORT}" ]] && GATEWAY_HTTPS_HOST_PORT=443

echo "=== Security checks ==="
echo ""

# -------------------------------------------------------------------------
# 1. WireGuard encryption
# -------------------------------------------------------------------------
echo "--- WireGuard transparent encryption ---"
if [[ "${EXPECT_WIREGUARD}" == "true" ]]; then
  wg_status=$(kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
    cilium-dbg status 2>/dev/null | grep -i "Encryption" || true)
  if echo "${wg_status}" | grep -qi "wireguard"; then
    ok "Cilium WireGuard encryption is active: ${wg_status}"
  else
    fail_soft "WireGuard not detected in Cilium status (enable_cilium_wireguard=true)"
    warn "cilium-dbg status output: ${wg_status:-<empty>}"
  fi

  peer_count=$(kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
    cilium-dbg status 2>/dev/null | sed -nE 's/.*Peers: ([0-9]+).*/\1/p' | head -n 1)
  [[ -n "${peer_count}" ]] || peer_count="0"
  if [[ "${peer_count}" -gt 0 ]]; then
    ok "WireGuard has ${peer_count} peer(s)"
  else
    fail_soft "WireGuard has 0 peers (expected >= 1 for multi-node)"
  fi
else
  skip "WireGuard not enabled (enable_cilium_wireguard=${EXPECT_WIREGUARD:-unset})"
fi
echo ""

# -------------------------------------------------------------------------
# 2. TLS 1.3 on the platform gateway
# -------------------------------------------------------------------------
echo "--- TLS 1.3 enforcement on platform gateway ---"
if [[ "${EXPECT_GATEWAY_TLS}" == "true" ]]; then
  port_suffix=""
  [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]] && port_suffix=":${GATEWAY_HTTPS_HOST_PORT}"

  if have_cmd openssl; then
    tls_info=$(echo | openssl s_client \
      -connect "127.0.0.1:${GATEWAY_HTTPS_HOST_PORT}" \
      -servername "argocd.admin.127.0.0.1.sslip.io" \
      -tls1_3 2>&1 || true)

    if echo "${tls_info}" | grep -q "TLSv1.3"; then
      ok "TLS 1.3 connection successful to platform gateway"
    else
      fail_soft "TLS 1.3 connection failed to platform gateway"
    fi

    # Prove the negative: TLS 1.2 should be rejected
    tls12_info=$(echo | openssl s_client \
      -connect "127.0.0.1:${GATEWAY_HTTPS_HOST_PORT}" \
      -servername "argocd.admin.127.0.0.1.sslip.io" \
      -tls1_2 2>&1 || true)

    if echo "${tls12_info}" | grep -qE "alert protocol version|no protocols available|handshake failure|wrong version"; then
      ok "TLS 1.2 correctly rejected by platform gateway (negative test)"
    else
      if echo "${tls12_info}" | grep -q "TLSv1.2"; then
        fail_soft "TLS 1.2 still accepted by platform gateway (should be TLS 1.3 only)"
      else
        warn "TLS 1.2 test inconclusive (gateway may not be reachable)"
      fi
    fi
  else
    skip "openssl not found; skipping black-box TLS probes"
  fi

  # Check HTTP/2 ALPN
  if have_cmd curl; then
    h2_check=$(curl -sk --http2 -o /dev/null -w '%{http_version}' \
      "https://argocd.admin.127.0.0.1.sslip.io${port_suffix}/" 2>/dev/null || true)
    if [[ "${h2_check}" == "2" ]]; then
      ok "HTTP/2 negotiated via ALPN"
    else
      warn "HTTP/2 not negotiated (got version: ${h2_check:-unknown})"
    fi
  fi

  # Check security headers
  if have_cmd curl; then
    headers=$(curl -skI "https://argocd.admin.127.0.0.1.sslip.io${port_suffix}/" 2>/dev/null || true)
    if echo "${headers}" | grep -qi "strict-transport-security"; then
      ok "HSTS header present"
    else
      warn "HSTS header missing"
    fi
    if echo "${headers}" | grep -qi "x-content-type-options.*nosniff"; then
      ok "X-Content-Type-Options: nosniff present"
    else
      warn "X-Content-Type-Options header missing"
    fi
  fi

  echo ""
  echo "--- Platform gateway config integrity ---"
  controller_args=$(kubectl -n nginx-gateway get deploy nginx-gateway \
    -o go-template='{{range (index .spec.template.spec.containers 0).args}}{{println .}}{{end}}' 2>/dev/null || true)
  if printf '%s\n' "${controller_args}" | grep -Fxq -- "--snippets"; then
    ok "NGINX Gateway controller has snippets enabled"
  else
    fail_soft "NGINX Gateway controller is missing --snippets, so SnippetsPolicy will not take effect"
  fi

  clusterrole_yaml=$(kubectl get clusterrole nginx-gateway -o yaml 2>/dev/null || true)
  if printf '%s\n' "${clusterrole_yaml}" | grep -Fq "snippetspolicies"; then
    ok "NGINX Gateway ClusterRole allows SnippetsPolicy watch access"
  else
    fail_soft "NGINX Gateway ClusterRole is missing SnippetsPolicy RBAC"
  fi
  if printf '%s\n' "${clusterrole_yaml}" | grep -Fq "snippetsfilters"; then
    ok "NGINX Gateway ClusterRole allows SnippetsFilter watch access"
  else
    fail_soft "NGINX Gateway ClusterRole is missing SnippetsFilter RBAC"
  fi

  nginx_conf=$(live_platform_gateway_nginx_conf)
  if [[ -z "${nginx_conf}" ]]; then
    fail_soft "Could not read live platform gateway NGINX config"
  else
    while IFS= read -r directive; do
      [[ -z "${directive}" ]] && continue
      if printf '%s\n' "${nginx_conf}" | grep -Fq -- "${directive}"; then
        ok "Rendered NGINX config includes: ${directive}"
      else
        fail_soft "Rendered NGINX config missing expected directive: ${directive}"
      fi
    done < <(expected_platform_gateway_tls_directives)
  fi
else
  skip "Gateway TLS checks skipped (enable_gateway_tls=${EXPECT_GATEWAY_TLS:-unset})"
fi
echo ""

# -------------------------------------------------------------------------
# 3. Kyverno default-deny NetworkPolicies
# -------------------------------------------------------------------------
echo "--- Kyverno default-deny NetworkPolicies ---"
if [[ "${EXPECT_POLICIES}" == "true" ]]; then
  for ns in dev uat sit; do
    if kubectl -n "${ns}" get networkpolicy default-deny >/dev/null 2>&1; then
      ok "default-deny NetworkPolicy present in ${ns}"
    else
      fail_soft "default-deny NetworkPolicy missing in ${ns} (Kyverno should generate it via kyverno.io/isolate label)"
    fi
  done

  for ns in gitea gitea-runner headlamp sso observability; do
    if kubectl get ns "${ns}" >/dev/null 2>&1; then
      isolate_label=$(kubectl get ns "${ns}" -o jsonpath='{.metadata.labels.kyverno\.io/isolate}' 2>/dev/null || true)
      if [[ "${isolate_label}" == "true" ]]; then
        ok "Namespace ${ns} has kyverno.io/isolate=true"
        if kubectl -n "${ns}" get networkpolicy default-deny >/dev/null 2>&1; then
          ok "default-deny NetworkPolicy present in ${ns}"
        else
          warn "default-deny NetworkPolicy not yet generated for ${ns} (Kyverno may still be reconciling)"
        fi
      else
        fail_soft "Namespace ${ns} missing kyverno.io/isolate=true label"
      fi
    fi
  done
else
  skip "Kyverno policy checks skipped (enable_policies=${EXPECT_POLICIES:-unset})"
fi
echo ""

# -------------------------------------------------------------------------
# 4. Cilium network policy enforcement - prove the negative
# -------------------------------------------------------------------------
echo "--- Cilium policy enforcement (negative tests) ---"
if [[ "${EXPECT_POLICIES}" == "true" ]]; then
  # Test: sentiment pods in uat should NOT be able to reach subnetcalc pods
  sentiment_pod=$(kubectl -n uat get pods -l project=sentiment -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  subnetcalc_router_svc=$(kubectl -n uat get svc subnetcalc-router -o jsonpath='{.metadata.name}' 2>/dev/null || true)

  if [[ -n "${sentiment_pod}" && -n "${subnetcalc_router_svc}" ]]; then
    cross_project=$(kubectl -n uat exec "${sentiment_pod}" --request-timeout=5s -- \
      wget -q -O- --timeout=3 "http://${subnetcalc_router_svc}:8080/" 2>&1 || true)
    if echo "${cross_project}" | grep -qiE "timed out|connection refused|Network is unreachable|command terminated|exit code [1-9]"; then
      ok "Cross-project traffic blocked: sentiment cannot reach subnetcalc in uat (negative test)"
    else
      fail_soft "Cross-project traffic NOT blocked: sentiment CAN reach subnetcalc in uat"
    fi
  else
    skip "Cross-project isolation test skipped (pods not found: sentiment_pod=${sentiment_pod:-none}, subnetcalc_router_svc=${subnetcalc_router_svc:-none})"
  fi

  # Test: uat pods should NOT be able to reach gitea directly
  uat_pod=$(kubectl -n uat get pods -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -n "${uat_pod}" ]]; then
    gitea_reach=$(kubectl -n uat exec "${uat_pod}" --request-timeout=5s -- \
      wget -q -O- --timeout=3 "http://gitea-http.gitea.svc.cluster.local:3000/" 2>&1 || true)
    if echo "${gitea_reach}" | grep -qiE "timed out|connection refused|Network is unreachable|command terminated|exit code [1-9]"; then
      ok "UAT pods cannot reach Gitea directly (negative test)"
    else
      warn "UAT pods may be able to reach Gitea (policy may be additive with baseline)"
    fi
  else
    skip "UAT-to-Gitea isolation test skipped (no uat pods found)"
  fi

  # Test: uat pods should NOT be able to reach argocd directly
  if [[ -n "${uat_pod}" ]]; then
    argocd_reach=$(kubectl -n uat exec "${uat_pod}" --request-timeout=5s -- \
      wget -q -O- --timeout=3 "http://argocd-server.argocd.svc.cluster.local:8080/" 2>&1 || true)
    if echo "${argocd_reach}" | grep -qiE "timed out|connection refused|Network is unreachable|command terminated|exit code [1-9]"; then
      ok "UAT pods cannot reach ArgoCD directly (negative test)"
    else
      warn "UAT pods may be able to reach ArgoCD (policy may be additive with baseline)"
    fi
  else
    skip "UAT-to-ArgoCD isolation test skipped (no uat pods found)"
  fi
else
  skip "Cilium policy enforcement tests skipped (enable_policies=${EXPECT_POLICIES:-unset})"
fi
echo ""

# -------------------------------------------------------------------------
# 5. Namespace labels audit
# -------------------------------------------------------------------------
echo "--- Namespace labels audit ---"
for ns in uat dev sit; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    labels=$(kubectl get ns "${ns}" -o jsonpath='{.metadata.labels}' 2>/dev/null || true)
    ok "Namespace ${ns} labels: ${labels}"
  fi
done

uat_sensitivity=$(kubectl get ns uat -o go-template='{{ index .metadata.labels "platform.publiccloudexperiments.net/sensitivity" }}' 2>/dev/null || true)
if [[ "${uat_sensitivity}" == "private" ]]; then
  ok "UAT namespace has sensitivity=private"
else
  warn "UAT namespace missing sensitivity=private label (got: ${uat_sensitivity:-<empty>})"
fi
echo ""

# -------------------------------------------------------------------------
# 6. Image registry audit (runtime check)
# -------------------------------------------------------------------------
echo "--- Image registry audit (uat namespace) ---"
if kubectl get ns uat >/dev/null 2>&1; then
  APPROVED_PREFIXES="quay.io/ ghcr.io/ docker.io/ dhi.io/ docker.gitea.com/ ecr-public.aws.com/ otel/ signoz/ gitea/ curlimages/ localhost:30090/"
  unapproved=0
  while IFS= read -r image; do
    [[ -z "${image}" ]] && continue
    approved=0
    for prefix in ${APPROVED_PREFIXES}; do
      if [[ "${image}" == ${prefix}* ]]; then
        approved=1
        break
      fi
    done
    # Also allow short-form images (nginx:*, python:*, docker:*)
    if [[ "${approved}" -eq 0 ]]; then
      case "${image}" in
        nginx:*|python:*|docker:*|node:*) approved=1 ;;
      esac
    fi
    if [[ "${approved}" -eq 0 ]]; then
      warn "Unapproved image in uat: ${image}"
      unapproved=$((unapproved + 1))
    fi
  done < <(kubectl -n uat get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null)

  if [[ "${unapproved}" -eq 0 ]]; then
    ok "All images in uat are from approved registries"
  else
    fail_soft "${unapproved} unapproved image(s) found in uat"
  fi
else
  skip "Image registry audit skipped (uat namespace not found)"
fi
echo ""

# -------------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------------
echo "=== Security check summary ==="
if [[ "${FAILURES}" -gt 0 ]]; then
  fail "Security check failed (${FAILURES} issue(s))"
fi
ok "All security checks passed"
