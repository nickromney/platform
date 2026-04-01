#!/bin/bash
# Setup PKI with step-ca for mTLS
# Reads CLOUD_NUM, CLOUD_NAME, PROJECT_DIR from environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Configure PKI assets for the current SD-WAN Lima guest.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would configure PKI assets for the current SD-WAN Lima guest" "$@"

# Parent provisioners may run with xtrace enabled; turn it off here so
# private keys, CA material, and leaf cert generation do not end up in logs.
set +x

echo "=== Setting up PKI for $CLOUD_NAME ==="

PKI_DIR="/etc/pki"
SHARED_PKI="/tmp/lima/pki"
mkdir -p "$PKI_DIR" "$SHARED_PKI"

STEP_BIN=$(command -v step || true)
if [ -z "$STEP_BIN" ] && [ -x /usr/local/bin/step ]; then
    STEP_BIN=/usr/local/bin/step
fi
if [ -z "$STEP_BIN" ]; then
    echo "ERROR: step CLI not found"
    exit 1
fi

# --- Root CA (shared across all clouds) ---
# First VM to run creates the root CA; others reuse it via shared mount
if [ ! -f "$SHARED_PKI/root-ca.crt" ]; then
    echo "Generating root CA (first VM)..."
    "$STEP_BIN" certificate create "SD-WAN Root CA" \
        "$SHARED_PKI/root-ca.crt" "$SHARED_PKI/root-ca.key" \
        --profile root-ca \
        --no-password --insecure \
        --not-after 87600h
else
    echo "Root CA already exists, reusing..."
fi

cp "$SHARED_PKI/root-ca.crt" "$PKI_DIR/root-ca.crt"
cp "$SHARED_PKI/root-ca.key" "$PKI_DIR/root-ca.key"

# --- Intermediate CA (per cloud) ---
echo "Generating intermediate CA for $CLOUD_NAME..."
"$STEP_BIN" certificate create "${CLOUD_NAME} Intermediate CA" \
    "$PKI_DIR/intermediate.crt" "$PKI_DIR/intermediate.key" \
    --profile intermediate-ca \
    --ca "$PKI_DIR/root-ca.crt" --ca-key "$PKI_DIR/root-ca.key" \
    --no-password --insecure \
    --not-after 43800h

# Create full chain (intermediate + root)
cat "$PKI_DIR/intermediate.crt" "$PKI_DIR/root-ca.crt" > "$PKI_DIR/ca-chain.crt"

# --- Server certificate ---
# Build SAN list based on cloud
SERVER_SANS=()
case "$CLOUD_NUM" in
    1)
        SERVER_SANS=(--san inbound.cloud1.test --san app1.cloud1.test --san dns.cloud1.test --san db.cloud1.test --san 10.10.1.60 --san 172.16.10.1)
        ;;
    2)
        SERVER_SANS=(--san inbound.cloud2.test --san api1.cloud2.test --san api1.vanity.test --san dns.cloud2.test --san 10.10.1.60 --san 172.16.11.2)
        ;;
    3)
        SERVER_SANS=(--san inbound.cloud3.test --san app2.cloud3.test --san dns.cloud3.test --san 10.10.1.60 --san 172.16.12.3)
        ;;
esac

echo "Generating server certificate for $CLOUD_NAME..."
"$STEP_BIN" certificate create "inbound.${CLOUD_NAME}.test" \
    "$PKI_DIR/server.crt" "$PKI_DIR/server.key" \
    --profile leaf \
    --ca "$PKI_DIR/intermediate.crt" --ca-key "$PKI_DIR/intermediate.key" \
    --no-password --insecure \
    --not-after 8760h \
    "${SERVER_SANS[@]}"
cat "$PKI_DIR/server.crt" "$PKI_DIR/intermediate.crt" > "$PKI_DIR/server-fullchain.crt"

# --- Client certificate (for outbound mTLS to other clouds) ---
echo "Generating client certificate for $CLOUD_NAME..."
"$STEP_BIN" certificate create "${CLOUD_NAME}-client" \
    "$PKI_DIR/client.crt" "$PKI_DIR/client.key" \
    --profile leaf \
    --ca "$PKI_DIR/root-ca.crt" --ca-key "$PKI_DIR/root-ca.key" \
    --no-password --insecure \
    --not-after 8760h

# --- App service certificate (for backend mTLS) ---
echo "Generating app service certificate for $CLOUD_NAME..."
case "$CLOUD_NUM" in
    1) APP_CN="app1.cloud1.test"; APP_SAN=(--san app1.cloud1.test --san 10.10.1.4) ;;
    2) APP_CN="api1.cloud2.test"; APP_SAN=(--san api1.cloud2.test --san api1.vanity.test --san 10.10.1.4) ;;
    3) APP_CN="app2.cloud3.test"; APP_SAN=(--san app2.cloud3.test --san 172.31.1.1) ;;
esac

"$STEP_BIN" certificate create "$APP_CN" \
    "$PKI_DIR/app-server.crt" "$PKI_DIR/app-server.key" \
    --profile leaf \
    --ca "$PKI_DIR/intermediate.crt" --ca-key "$PKI_DIR/intermediate.key" \
    --no-password --insecure \
    --not-after 8760h \
    "${APP_SAN[@]}"

# Set permissions
chmod 600 "$PKI_DIR"/*.key
chmod 644 "$PKI_DIR"/*.crt

echo "=== PKI setup complete for $CLOUD_NAME ==="
echo "  Root CA:      $PKI_DIR/root-ca.crt"
echo "  Intermediate: $PKI_DIR/intermediate.crt"
echo "  Server cert:  $PKI_DIR/server-fullchain.crt"
echo "  Client cert:  $PKI_DIR/client.crt"
echo "  App cert:     $PKI_DIR/app-server.crt"
