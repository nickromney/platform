#!/bin/sh
# Split-Brain DNS Test Script

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)

. "${REPO_ROOT}/scripts/lib/shell-cli-posix.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the SD-WAN split-brain DNS demonstration.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the SD-WAN split-brain DNS demonstration" "$@"

apk add --no-cache bind-tools >/dev/null 2>&1

echo "=============================================="
echo "  Split-Brain DNS Demonstration"
echo "=============================================="
echo ""
echo "Same domain returns DIFFERENT IPs based on which"
echo "DNS server you query (internal vs external)"
echo ""

echo ">>> TEST 1: Direct to INTERNAL DNS (10.1.0.10)"
echo "    Returns RFC1918 address for direct overlay access"
dig @10.1.0.10 app.cloud1.test A +short
echo ""

echo ">>> TEST 2: Direct to EXTERNAL DNS (172.16.1.10)"
echo "    Returns public address (NAT'd)"
dig @172.16.1.10 app.cloud1.test A +short
echo ""

echo ">>> TEST 3: Direct to INTERNAL DNS - Cloud 2"
dig @10.2.0.10 app.cloud2.test A +short
echo ""

echo ">>> TEST 4: Direct to EXTERNAL DNS - Cloud 2"
dig @172.16.2.10 app.cloud2.test A +short
echo ""

echo ">>> TEST 5: Cross-cloud query (cloud1 -> cloud2)"
dig @10.1.0.10 app.cloud2.test A +short
echo ""

echo "=============================================="
echo "  Summary"
echo ""
echo "Internal DNS (10.x.x.x) returns: RFC1918"
echo "External DNS (172.16.x.x) returns: Public-like"
echo ""
echo "This simulates SD-WAN:"
echo "  - On-prem/overlay clients use internal DNS -> RFC1918"
echo "  - Remote/public clients use external DNS -> Public IPs"
