#!/bin/bash
# Egress firewall (iptables) tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the SD-WAN egress firewall verification suite.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the SD-WAN egress firewall verification suite" "$@"

PASS=0
FAIL=0

echo "--- Egress firewall blocks external traffic ---"
# Traffic to public internet should be blocked
result=$(limactl shell cloud1 -- bash -c "curl -sS --connect-timeout 3 http://1.1.1.1" 2>&1 || true)
if [ -z "$result" ] || echo "$result" | grep -qiE "timed out|refused|unreachable|failed|could not connect|network is unreachable"; then
    echo "  PASS: External traffic (1.1.1.1) blocked from cloud1 internal"
    PASS=$((PASS + 1))
else
    echo "  FAIL: External traffic should be blocked (got: $(echo "$result" | head -1))"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Iptables counters show matched packets ---"
for cloud in cloud1 cloud2 cloud3; do
    echo "  $cloud iptables FORWARD chain:"
    limactl shell "$cloud" -- sudo iptables -L FORWARD -n -v 2>/dev/null | head -10 || true
    echo ""
done

echo ""
echo "--- NAT rules present ---"
for cloud in cloud1 cloud2 cloud3; do
    nat_rules=$(limactl shell "$cloud" -- sudo iptables -t nat -L -n 2>/dev/null | grep -c "MASQUERADE\|DNAT" || true)
    if [ "$nat_rules" -gt 0 ]; then
        echo "  PASS: $cloud has $nat_rules NAT rules"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $cloud has no NAT rules"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Egress Tests: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
