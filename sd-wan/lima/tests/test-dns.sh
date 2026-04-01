#!/bin/bash
# DNS split-brain verification tests
# Tests that overlapping IPs resolve correctly per cloud
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the SD-WAN DNS split-brain verification suite.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the SD-WAN DNS verification suite" "$@"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local cloud="$2"
    local cmd="$3"
    local expected="$4"

    result=$(limactl shell "$cloud" -- bash -c "$cmd" 2>/dev/null | tr -d '[:space:]')
    expected_clean=$(echo "$expected" | tr -d '[:space:]')

    if [ "$result" = "$expected_clean" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$result')"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- Cloud1 (Azure) internal DNS ---"
check "app1.cloud1.test -> 10.10.1.4" cloud1 \
    "dig @10.10.1.10 app1.cloud1.test +short" "10.10.1.4"
check "dns.cloud1.test -> 10.10.1.10" cloud1 \
    "dig @10.10.1.10 dns.cloud1.test +short" "10.10.1.10"
check "db.cloud1.test -> 10.10.1.40" cloud1 \
    "dig @10.10.1.10 db.cloud1.test +short" "10.10.1.40"

echo ""
echo "--- Cloud2 (on-prem) internal DNS ---"
check "api1.cloud2.test -> 10.10.1.4" cloud2 \
    "dig @10.10.1.10 api1.cloud2.test +short" "10.10.1.4"
check "dns.cloud2.test -> 10.10.1.10" cloud2 \
    "dig @10.10.1.10 dns.cloud2.test +short" "10.10.1.10"

echo ""
echo "--- Cloud3 (AWS) internal DNS ---"
check "app2.cloud3.test -> 172.31.1.1" cloud3 \
    "dig @172.31.1.10 app2.cloud3.test +short" "172.31.1.1"
check "dns.cloud3.test -> 172.31.1.10" cloud3 \
    "dig @172.31.1.10 dns.cloud3.test +short" "172.31.1.10"

echo ""
echo "--- Cross-cloud vanity DNS ---"
check "api1.vanity.test from cloud1 -> 172.16.11.2" cloud1 \
    "dig @10.10.1.10 api1.vanity.test +short" "172.16.11.2"
check "api1.vanity.test from cloud3 -> 172.16.11.2" cloud3 \
    "dig @172.31.1.10 api1.vanity.test +short" "172.16.11.2"

echo ""
echo "--- DNS isolation: tunnel addresses NOT in app DNS ---"
# Tunnel addresses should not be resolvable from app DNS
result=$(limactl shell cloud1 -- bash -c "dig @10.10.1.10 tunnel.cloud2.test +short" 2>/dev/null | tr -d '[:space:]')
if [ -z "$result" ]; then
    echo "  PASS: tunnel.cloud2.test returns NXDOMAIN from cloud1 app DNS"
    PASS=$((PASS + 1))
else
    echo "  FAIL: tunnel.cloud2.test should not resolve from app DNS (got '$result')"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Overlap proof: same IP, different services ---"
cloud1_name=$(limactl shell cloud1 -- bash -c "dig @10.10.1.10 app1.cloud1.test +short" 2>/dev/null | tr -d '[:space:]')
cloud2_name=$(limactl shell cloud2 -- bash -c "dig @10.10.1.10 api1.cloud2.test +short" 2>/dev/null | tr -d '[:space:]')
if [ "$cloud1_name" = "10.10.1.4" ] && [ "$cloud2_name" = "10.10.1.4" ]; then
    echo "  PASS: Both cloud1 and cloud2 resolve to 10.10.1.4 (different services)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Overlap proof failed"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== DNS Tests: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
