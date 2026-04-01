#!/bin/bash
# End-to-end routing tests
# Tests the full flow: app -> DNS -> outbound -> WireGuard -> inbound -> backend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the SD-WAN end-to-end routing verification suite.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the SD-WAN routing verification suite" "$@"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local cloud="$2"
    local cmd="$3"
    local expected="$4"

    result=$(limactl shell "$cloud" -- bash -c "$cmd" 2>/dev/null || true)

    if echo "$result" | grep -q "$expected"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $expected"
        echo "    got: $(echo "$result" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- Cross-cloud via vanity domain (mTLS) ---"
check "cloud1 -> api1.vanity.test reaches cloud2" cloud1 \
    "sudo curl -s --cert /etc/pki/client.crt --key /etc/pki/client.key --cacert /etc/pki/root-ca.crt https://api1.vanity.test/api/v1/health 2>/dev/null || sudo curl -s --cert /etc/pki/client.crt --key /etc/pki/client.key --cacert /etc/pki/root-ca.crt --resolve api1.vanity.test:443:172.16.11.2 https://api1.vanity.test/api/v1/health" \
    "healthy"

echo ""
echo "--- Inbound proxy with TLS ---"
check "cloud1 -> cloud2 inbound VIP returns cloud2 response" cloud1 \
    "sudo curl -s --cert /etc/pki/client.crt --key /etc/pki/client.key --cacert /etc/pki/root-ca.crt https://172.16.11.2/api/v1/health 2>/dev/null" \
    "healthy"

echo ""
echo "--- Backend payload verification ---"
check "Inbound VIP returns subnet API payload" cloud1 \
    "sudo curl -s --cert /etc/pki/client.crt --key /etc/pki/client.key --cacert /etc/pki/root-ca.crt https://172.16.11.2/api/v1/health 2>/dev/null" \
    "Subnet Calculator API"

echo ""
echo "--- Local backend health on cloud2 ---"
cloud2_resp=$(limactl shell cloud2 -- curl -s http://10.10.1.4:8000/api/v1/health 2>/dev/null || echo "")

if echo "$cloud2_resp" | grep -q "healthy"; then
    echo "  PASS: cloud2 local backend health endpoint is reachable"
    PASS=$((PASS + 1))
else
    echo "  FAIL: cloud2 local backend health endpoint is not reachable"
    echo "    cloud2: $(echo "$cloud2_resp" | head -1)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Routing Tests: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
