#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }
warn() { echo "WARN $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

SLICER_VM_NAME="${SLICER_VM_NAME:-sbox-1}"
SLICER_URL="${SLICER_URL:-${SLICER_SOCKET:-}}"
DEX_HOST="${DEX_HOST:-dex.127.0.0.1.sslip.io}"
DEX_NAMESPACE="${DEX_NAMESPACE:-sso}"
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://dex.127.0.0.1.sslip.io/dex}"
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-headlamp}"
MKCERT_CA_DEST="${MKCERT_CA_DEST:-/etc/rancher/k3s/mkcert-rootCA.pem}"
K3S_CONFIG_FRAGMENT="${K3S_CONFIG_FRAGMENT:-/etc/rancher/k3s/config.yaml.d/90-headlamp-oidc.yaml}"
PLATFORM_GATEWAY_NAMESPACE="${PLATFORM_GATEWAY_NAMESPACE:-platform-gateway}"
PLATFORM_GATEWAY_INTERNAL_SVC="${PLATFORM_GATEWAY_INTERNAL_SVC:-platform-gateway-nginx-internal}"
GATEWAY_DEPLOY_NAME="${GATEWAY_DEPLOY_NAME:-platform-gateway-nginx}"
PLATFORM_GATEWAY_NAME="${PLATFORM_GATEWAY_NAME:-platform-gateway}"
PLATFORM_GATEWAY_TLS_SECRET="${PLATFORM_GATEWAY_TLS_SECRET:-platform-gateway-tls}"
GATEWAY_DEPLOY_WAIT_SECONDS="${GATEWAY_DEPLOY_WAIT_SECONDS:-900}"
OIDC_DISCOVERY_WAIT_SECONDS="${OIDC_DISCOVERY_WAIT_SECONDS:-900}"

[ -n "${SLICER_URL}" ] || fail "SLICER_URL or SLICER_SOCKET must be set"

slicer_exec() {
  local name="$1"
  shift
  SLICER_URL="${SLICER_URL}" slicer vm exec "$name" -- "$@"
}

remote_read_file() {
  local path="$1"
  slicer_exec "$SLICER_VM_NAME" "sudo sh -c \"cat '$path' 2>/dev/null || true\""
}

remote_write_file() {
  local path="$1"
  local content="$2"
  slicer_exec "$SLICER_VM_NAME" "sudo mkdir -p \"$(dirname "$path")\""
  printf '%s\n' "$content" | slicer_exec "$SLICER_VM_NAME" "sudo tee \"$path\" >/dev/null"
}

ensure_remote_file_equals() {
  local path="$1"
  local desired="$2"
  local current

  current="$(remote_read_file "$path")"
  if [[ "$current" == "$desired" ]]; then
    return 1
  fi

  remote_write_file "$path" "$desired"
  return 0
}

ensure_remote_host_alias() {
  local desired_ip="$1"

  slicer_exec "$SLICER_VM_NAME" "sudo env DEX_HOST='${DEX_HOST}' GATEWAY_IP='${desired_ip}' bash -s" <<'EOF'
set -euo pipefail

tmp="$(mktemp)"
grep -vE "[[:space:]]${DEX_HOST//./\\.}([[:space:]]|$)" /etc/hosts >"$tmp"
printf '%s %s\n' "$GATEWAY_IP" "$DEX_HOST" >>"$tmp"

if ! cmp -s "$tmp" /etc/hosts; then
  cat "$tmp" >/etc/hosts
  echo changed
fi

rm -f "$tmp"
EOF
}

ensure_remote_ca() {
  local source_ca="$1"
  local dest_path="$2"
  local local_sha remote_sha

  local_sha="$(shasum -a 256 "$source_ca" | awk '{print $1}')"
  remote_sha="$(slicer_exec "$SLICER_VM_NAME" "sudo sh -c \"sha256sum '$dest_path' 2>/dev/null | cut -d' ' -f1\"" || true)"

  if [[ "$local_sha" == "$remote_sha" ]]; then
    return 1
  fi

  SLICER_URL="${SLICER_URL}" slicer vm cp "$source_ca" "${SLICER_VM_NAME}:/tmp/mkcert-rootCA.pem" >/dev/null
  slicer_exec "$SLICER_VM_NAME" "sudo mkdir -p \"$(dirname "$dest_path")\" && sudo mv /tmp/mkcert-rootCA.pem '$dest_path'"
  return 0
}

usage() {
  cat <<'EOF'
Usage: configure-k3s-apiserver-oidc.sh

Configures the Slicer-backed k3s server so Dex-issued Headlamp OIDC tokens are
accepted by the Kubernetes API. This mutates the guest VM.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd slicer
require_cmd kubectl
require_cmd curl
require_cmd shasum

if ! command -v mkcert >/dev/null 2>&1; then
  warn "mkcert not found; skipping Slicer apiserver OIDC configuration"
  exit 0
fi

CAROOT="$(mkcert -CAROOT)"
CA_CERT="${CAROOT}/rootCA.pem"
if [[ ! -f "$CA_CERT" ]]; then
  warn "mkcert CA cert not found at ${CA_CERT}; skipping Slicer apiserver OIDC configuration"
  exit 0
fi

GATEWAY_IP="$(kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" get svc "$PLATFORM_GATEWAY_INTERNAL_SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
if [[ -z "$GATEWAY_IP" ]]; then
  fail "Could not determine clusterIP for svc ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_INTERNAL_SVC}"
fi

ok "Slicer node: ${SLICER_VM_NAME}"
ok "gateway internal clusterIP: ${GATEWAY_IP}"

ok "waiting for gateway data plane (${PLATFORM_GATEWAY_NAMESPACE}/${GATEWAY_DEPLOY_NAME})"
gw_end=$((SECONDS + GATEWAY_DEPLOY_WAIT_SECONDS))
while (( SECONDS < gw_end )); do
  if kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" rollout status "deploy/${GATEWAY_DEPLOY_NAME}" --timeout=10s >/dev/null 2>&1; then
    ok "gateway data plane ready"
    break
  fi
  sleep 5
done
if (( SECONDS >= gw_end )); then
  warn "gateway data plane not ready after ${GATEWAY_DEPLOY_WAIT_SECONDS}s"
  kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" get pods -l "gateway.networking.k8s.io/gateway-name=${PLATFORM_GATEWAY_NAME}" -o wide 2>/dev/null || true
  fail "gateway data plane never became ready; aborting OIDC apiserver configuration"
fi

ok "waiting for TLS secret ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_TLS_SECRET}"
tls_end=$((SECONDS + GATEWAY_DEPLOY_WAIT_SECONDS))
while (( SECONDS < tls_end )); do
  if kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" get secret "$PLATFORM_GATEWAY_TLS_SECRET" >/dev/null 2>&1; then
    ok "gateway TLS secret present"
    break
  fi
  sleep 2
done
if (( SECONDS >= tls_end )); then
  fail "gateway TLS secret ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_TLS_SECRET} was never created"
fi

ok "waiting for Gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} to be programmed"
gw_prog_end=$((SECONDS + GATEWAY_DEPLOY_WAIT_SECONDS))
while (( SECONDS < gw_prog_end )); do
  gateway_programmed="$(kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" get gateway "$PLATFORM_GATEWAY_NAME" -o jsonpath='{range .status.conditions[?(@.type=="Programmed")]}{.status}{end}' 2>/dev/null || true)"
  gateway_accepted="$(kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" get gateway "$PLATFORM_GATEWAY_NAME" -o jsonpath='{range .status.conditions[?(@.type=="Accepted")]}{.status}{end}' 2>/dev/null || true)"
  if [[ "$gateway_programmed" == "True" && "$gateway_accepted" == "True" ]]; then
    ok "gateway listener programmed"
    break
  fi
  sleep 2
done
if (( SECONDS >= gw_prog_end )); then
  kubectl -n "$PLATFORM_GATEWAY_NAMESPACE" get gateway "$PLATFORM_GATEWAY_NAME" -o yaml || true
  fail "gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} never became programmed"
fi

ok "waiting for Dex deployment (${DEX_NAMESPACE}/dex)"
kubectl -n "$DEX_NAMESPACE" rollout status deploy/dex --timeout=10m >/dev/null 2>&1 || true

ok "ensuring ${DEX_HOST} resolves inside Slicer VM"
hosts_changed="$(ensure_remote_host_alias "$GATEWAY_IP" || true)"

ok "copying mkcert root CA into Slicer VM: ${MKCERT_CA_DEST}"
ca_changed=0
if ensure_remote_ca "$CA_CERT" "$MKCERT_CA_DEST"; then
  ca_changed=1
fi

desired_fragment="$(cat <<EOF
kube-apiserver-arg:
  - oidc-issuer-url=${OIDC_ISSUER_URL}
  - oidc-client-id=${OIDC_CLIENT_ID}
  - oidc-username-claim=email
  - oidc-groups-claim=groups
  - oidc-ca-file=${MKCERT_CA_DEST}
EOF
)"

ok "writing k3s config fragment: ${K3S_CONFIG_FRAGMENT}"
config_changed=0
if ensure_remote_file_equals "$K3S_CONFIG_FRAGMENT" "$desired_fragment"; then
  config_changed=1
fi

if [[ -n "$hosts_changed" || "$ca_changed" == "1" || "$config_changed" == "1" ]]; then
  ok "restarting k3s to apply OIDC settings"
  slicer_exec "$SLICER_VM_NAME" "sudo systemctl restart k3s"
else
  ok "k3s OIDC settings already current"
fi

ok "waiting for OIDC issuer discovery endpoint from Slicer VM"
end=$((SECONDS + OIDC_DISCOVERY_WAIT_SECONDS))
while (( SECONDS < end )); do
  if slicer_exec "$SLICER_VM_NAME" "sudo curl -fsS --max-time 5 --cacert '${MKCERT_CA_DEST}' '${OIDC_ISSUER_URL}/.well-known/openid-configuration'" >/dev/null; then
    ok "OIDC issuer reachable from Slicer VM: ${OIDC_ISSUER_URL}"
    break
  fi
  sleep 2
done
if (( SECONDS >= end )); then
  fail "timed out waiting for ${OIDC_ISSUER_URL}/.well-known/openid-configuration (from Slicer VM)"
fi

ok "waiting for kube-apiserver readiness"
for _ in $(seq 1 60); do
  if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    ok "kube-apiserver ready"
    exit 0
  fi
  sleep 2
done

fail "timed out waiting for kube-apiserver readiness"
