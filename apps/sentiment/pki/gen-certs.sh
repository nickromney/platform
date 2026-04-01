#!/bin/bash
# Generate local development PKI for TLS 1.3 compose experiment
# Uses step CLI (same toolchain as platforms/lima)
#
# Usage: ./gen-certs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: gen-certs.sh [--dry-run] [--execute]

Generate or refresh the local development PKI for the sentiment compose stack.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would generate or refresh sentiment local development certificates under ${SCRIPT_DIR}" "$@"

print_install_hint() {
    local tool="$1"
    if [ -x "${INSTALL_HINTS}" ]; then
        echo "Install hint:" >&2
        "${INSTALL_HINTS}" --plain "${tool}" >&2 || true
    fi
}

STEP_BIN=$(command -v step 2>/dev/null || echo "")
if [ -z "$STEP_BIN" ]; then
    echo "ERROR: step CLI not found"
    print_install_hint "step"
    exit 1
fi

echo "=== Generating local dev PKI (sentiment) ==="

# Root CA (reuse if already exists to allow cert renewal without re-trusting the CA)
if [ ! -f "$SCRIPT_DIR/root-ca.crt" ]; then
    echo "Generating root CA..."
    "$STEP_BIN" certificate create "sentiment Local Dev CA" \
        "$SCRIPT_DIR/root-ca.crt" "$SCRIPT_DIR/root-ca.key" \
        --profile root-ca \
        --no-password --insecure \
        --not-after 87600h
else
    echo "Root CA already exists, reusing (delete root-ca.crt to regenerate)"
fi

# Server cert — 90 days (Mozilla Modern recommendation)
echo "Generating server certificate (90 days)..."
"$STEP_BIN" certificate create "localhost" \
    "$SCRIPT_DIR/server.crt" "$SCRIPT_DIR/server.key" \
    --profile leaf \
    --ca "$SCRIPT_DIR/root-ca.crt" \
    --ca-key "$SCRIPT_DIR/root-ca.key" \
    --no-password --insecure \
    --not-after 2160h \
    --san localhost \
    --san 127.0.0.1

# Full chain for nginx ssl_certificate
cat "$SCRIPT_DIR/server.crt" "$SCRIPT_DIR/root-ca.crt" > "$SCRIPT_DIR/server-fullchain.crt"

chmod 600 "$SCRIPT_DIR"/*.key
chmod 644 "$SCRIPT_DIR"/*.crt

echo ""
echo "=== PKI setup complete ==="
echo "  CA:    $SCRIPT_DIR/root-ca.crt"
echo "  Cert:  $SCRIPT_DIR/server-fullchain.crt"
echo "  Key:   $SCRIPT_DIR/server.key"
echo ""
echo "To trust the CA on macOS (removes browser warnings):"
echo "  sudo security add-trusted-cert -d -r trustRoot \\"
echo "    -k /Library/Keychains/System.keychain \\"
echo "    $SCRIPT_DIR/root-ca.crt"
