#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

CLUSTER_NAME="${CLUSTER_NAME:-kind-local}"
DEX_HOST="${DEX_HOST:-dex.127.0.0.1.sslip.io}"
DEX_NAMESPACE="${DEX_NAMESPACE:-sso}"
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://dex.127.0.0.1.sslip.io/dex}"
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
GATEWAY_DEPLOY_WAIT_SECONDS="${GATEWAY_DEPLOY_WAIT_SECONDS:-900}"
OIDC_DISCOVERY_WAIT_SECONDS="${OIDC_DISCOVERY_WAIT_SECONDS:-900}"
GATEWAY_RECONCILE_WAIT_SECONDS="${GATEWAY_RECONCILE_WAIT_SECONDS:-300}"

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

restart_deployment() {
  local namespace="${1}"
  local deploy_name="${2}"
  local description="${3:-deployment ${namespace}/${deploy_name}}"

  if ! kubectl -n "${namespace}" get deploy "${deploy_name}" >/dev/null 2>&1; then
    warn "${description} not found; skipping controlled restart"
    return 0
  fi

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

usage() {
  cat <<'EOF'
Usage: configure-kind-apiserver-oidc.sh

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
  GATEWAY_DEPLOY_WAIT_SECONDS
  OIDC_DISCOVERY_WAIT_SECONDS
  GATEWAY_RECONCILE_WAIT_SECONDS

This is a local-dev helper; it mutates the kind node container and will restart
the kube-apiserver.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd kind
require_cmd kubectl
require_cmd docker
require_cmd curl

if ! command -v mkcert >/dev/null 2>&1; then
  warn "mkcert not found; skipping apiserver OIDC configuration"
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
kubectl -n "${DEX_NAMESPACE}" rollout status deploy/dex --timeout=10m >/dev/null 2>&1 || true

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

docker exec -i \
  -e MANIFEST="${MANIFEST}" \
  -e OIDC_ISSUER_URL="${OIDC_ISSUER_URL}" \
  -e OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
  -e MKCERT_CA_DEST="${MKCERT_CA_DEST}" \
  -e DEX_HOST="${DEX_HOST}" \
  -e GATEWAY_IP="${GATEWAY_IP}" \
  "${CONTROL_PLANE_NODE}" bash -s <<'EOF'
set -euo pipefail

if ! grep -q -- "--oidc-issuer-url=" "$MANIFEST"; then
  tmp=$(mktemp)
  awk -v issuer="$OIDC_ISSUER_URL" -v client="$OIDC_CLIENT_ID" -v ca="$MKCERT_CA_DEST" '
    /--service-cluster-ip-range=/{
      print
      print "    - --oidc-issuer-url=" issuer
      print "    - --oidc-client-id=" client
      print "    - --oidc-username-claim=email"
      print "    - --oidc-groups-claim=groups"
      print "    - --oidc-ca-file=" ca
      next
    }
    { print }
  ' "$MANIFEST" > "$tmp"
  mv "$tmp" "$MANIFEST"
fi

# kube-apiserver static pod uses its own /etc/hosts generated by kubelet.
# Ensure Dex host resolves to the in-cluster gateway service from inside the pod.
if ! grep -Fq -- "- ${DEX_HOST}" "$MANIFEST"; then
  tmp=$(mktemp)
  awk -v dex_host="$DEX_HOST" -v gateway_ip="$GATEWAY_IP" '
    /^  hostNetwork:/{
      print "  hostAliases:"
      print "  - ip: \"" gateway_ip "\""
      print "    hostnames:"
      print "    - " dex_host
      print
      print
      next
    }
    { print }
  ' "$MANIFEST" > "$tmp"
  mv "$tmp" "$MANIFEST"
fi
EOF

ok "waiting for kube-apiserver readiness (this may take ~30s)"
for _ in {1..60}; do
  if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    ok "kube-apiserver ready"
    break
  fi
  sleep 2
done

if ! kubectl get --raw='/readyz' >/dev/null 2>&1; then
  fail "timed out waiting for kube-apiserver readiness"
fi

restart_deployment \
  "${NGINX_GATEWAY_NAMESPACE}" \
  "${NGINX_GATEWAY_DEPLOY_NAME}" \
  "nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})"

ok "waiting for nginx gateway control plane after kube-apiserver restart"
wait_for_deployment_rollout \
  "${NGINX_GATEWAY_NAMESPACE}" \
  "${NGINX_GATEWAY_DEPLOY_NAME}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
  "nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})" \
  || fail "nginx gateway control plane did not recover after kube-apiserver restart"

wait_for_service_endpoints \
  "${NGINX_GATEWAY_NAMESPACE}" \
  "${NGINX_GATEWAY_SERVICE}" \
  "${GATEWAY_DEPLOY_WAIT_SECONDS}" \
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
