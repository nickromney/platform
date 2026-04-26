#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

RENDER_KIND_APISERVER_OIDC_MANIFEST="${SCRIPT_DIR}/render-kind-apiserver-oidc-manifest.py"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/kind-apiserver-oidc-lib.sh"

# shellcheck disable=SC2329
usage() {
  cat <<'EOF'
Usage: configure-kind-apiserver-oidc.sh [--dry-run] [--execute]

Configures the kind control-plane kube-apiserver static manifest for OIDC auth
against the configured SSO issuer so Headlamp OIDC tokens work against the K8s API.

This step is the explicit static-manifest bootstrap boundary. It prepares the
Gateway/SSO prerequisites, patches the kube-apiserver manifest, and waits for
the API server to become ready again. Runtime controller recovery is handled by
the separate recover-kind-cluster-after-apiserver-restart.sh step.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would configure the kind kube-apiserver OIDC settings" "$@"

require_cmd kind
require_cmd kubectl
require_cmd docker

if ! command -v mkcert >/dev/null 2>&1; then
  warn "mkcert not found; skipping apiserver OIDC configuration"
  print_install_hint "mkcert"
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

ok "waiting for ${SSO_DESCRIPTION} deployment (${SSO_NAMESPACE}/${SSO_DEPLOYMENT_NAME})"
if ! wait_for_deployment_rollout \
  "${SSO_NAMESPACE}" \
  "${SSO_DEPLOYMENT_NAME}" \
  "${OIDC_DISCOVERY_WAIT_SECONDS}" \
  "${SSO_DESCRIPTION} deployment (${SSO_NAMESPACE}/${SSO_DEPLOYMENT_NAME})"; then
  kubectl -n "${SSO_NAMESPACE}" get all -o wide 2>/dev/null || true
  fail "${SSO_DESCRIPTION} deployment never became ready"
fi

if ! wait_for_service_endpoints \
  "${SSO_NAMESPACE}" \
  "${SSO_SERVICE_NAME}" \
  "${OIDC_DISCOVERY_WAIT_SECONDS}"; then
  fail "${SSO_DESCRIPTION} service endpoints never became ready"
fi

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

ORIGINAL_MANIFEST_LOCAL="$(mktemp "${TMPDIR:-/tmp}/kube-apiserver-manifest.original.XXXXXX")"
RENDERED_MANIFEST_LOCAL="$(mktemp "${TMPDIR:-/tmp}/kube-apiserver-manifest.rendered.XXXXXX")"
CONTAINER_MANIFEST_BACKUP="${MANIFEST}.pre-oidc-backup"
CONTAINER_MANIFEST_CANDIDATE="${MANIFEST}.oidc-candidate"

trap 'rm -f "${ORIGINAL_MANIFEST_LOCAL}" "${RENDERED_MANIFEST_LOCAL}"; docker exec "${CONTROL_PLANE_NODE}" rm -f "${CONTAINER_MANIFEST_CANDIDATE}" >/dev/null 2>&1 || true' EXIT

docker cp "${CONTROL_PLANE_NODE}:${MANIFEST}" "${ORIGINAL_MANIFEST_LOCAL}"

[[ -f "${RENDER_KIND_APISERVER_OIDC_MANIFEST}" ]] || fail "render helper not found at ${RENDER_KIND_APISERVER_OIDC_MANIFEST}"
require_cmd uv

uv run --isolated python \
  "${RENDER_KIND_APISERVER_OIDC_MANIFEST}" \
  "${ORIGINAL_MANIFEST_LOCAL}" \
  "${RENDERED_MANIFEST_LOCAL}" \
  "${OIDC_ISSUER_URL}" \
  "${OIDC_CLIENT_ID}" \
  "${MKCERT_CA_DEST}" \
  "${DEX_HOST}" \
  "${GATEWAY_IP}"

if ! kubectl create --dry-run=client --validate=false -f "${RENDERED_MANIFEST_LOCAL}" >/dev/null 2>&1; then
  kubectl create --dry-run=client --validate=false -f "${RENDERED_MANIFEST_LOCAL}" >/dev/null
fi

if cmp -s "${ORIGINAL_MANIFEST_LOCAL}" "${RENDERED_MANIFEST_LOCAL}"; then
  ok "kube-apiserver manifest already matches desired OIDC config; no static-manifest change required"
  exit 0
fi

ok "installing kube-apiserver OIDC manifest update with rollback safety"
docker exec "${CONTROL_PLANE_NODE}" cp "${MANIFEST}" "${CONTAINER_MANIFEST_BACKUP}"
docker cp "${RENDERED_MANIFEST_LOCAL}" "${CONTROL_PLANE_NODE}:${CONTAINER_MANIFEST_CANDIDATE}"
docker exec "${CONTROL_PLANE_NODE}" mv "${CONTAINER_MANIFEST_CANDIDATE}" "${MANIFEST}"

ok "waiting for kube-apiserver readiness (this may take ~30s)"
if ! wait_for_kube_apiserver_ready 120 3; then
  warn "kube-apiserver did not recover after OIDC patch; restoring previous manifest"
  docker exec "${CONTROL_PLANE_NODE}" sh -lc \
    "cp '${CONTAINER_MANIFEST_BACKUP}' '${CONTAINER_MANIFEST_CANDIDATE}' && mv '${CONTAINER_MANIFEST_CANDIDATE}' '${MANIFEST}'"
  if wait_for_kube_apiserver_ready 120 3; then
    fail "timed out waiting for kube-apiserver readiness after OIDC patch; restored previous manifest"
  fi
  fail "timed out waiting for kube-apiserver readiness after OIDC patch, and rollback also failed"
fi

docker exec "${CONTROL_PLANE_NODE}" rm -f "${CONTAINER_MANIFEST_BACKUP}" >/dev/null 2>&1 || true

ok "kube-apiserver OIDC manifest applied successfully"
