#!/bin/sh
# DNS Test Script - runs DNS queries against all 3 clouds

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/../../.." && pwd)

. "${REPO_ROOT}/scripts/lib/shell-cli-posix.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run DNS checks against the configured SD-WAN resolver.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run SD-WAN DNS checks against resolver ${DNS_RESOLVER:-localhost}" "$@"

DNS_RESOLVER="${DNS_RESOLVER:-localhost}"

echo "=== DNS Test Suite ==="
echo "Testing resolver at: $DNS_RESOLVER"
echo ""

# Test Cloud 1
echo "--- Cloud 1 Tests ---"
echo "Query: cloud1.test A"
dig @"${DNS_RESOLVER}" cloud1.test A +short || echo "FAIL: cloud1.test"
echo ""

# Test Cloud 2
echo "--- Cloud 2 Tests ---"
echo "Query: cloud2.test A"
dig @"${DNS_RESOLVER}" cloud2.test A +short || echo "FAIL: cloud2.test"
echo ""

# Test Cloud 3
echo "--- Cloud 3 Tests ---"
echo "Query: cloud3.test A"
dig @"${DNS_RESOLVER}" cloud3.test A +short || echo "FAIL: cloud3.test"
echo ""

# Test cross-cloud resolution
echo "--- Cross-Cloud Tests ---"
echo "Query: app.cloud2.test A from cloud1 network"
dig @"${DNS_RESOLVER}" app.cloud2.test A +short || echo "FAIL: app.cloud2.test"
echo ""

echo "Query: app.cloud3.test A from cloud2 network"
dig @"${DNS_RESOLVER}" app.cloud3.test A +short || echo "FAIL: app.cloud3.test"
echo ""

# Test CNAME resolution
echo "--- CNAME Tests ---"
echo "Query: www.cloud1.test CNAME"
dig @"${DNS_RESOLVER}" www.cloud1.test CNAME +short || echo "FAIL: www.cloud1.test CNAME"
echo ""

echo "Query: api1.vanity.test CNAME"
dig @"${DNS_RESOLVER}" api1.vanity.test CNAME +short || echo "FAIL: api1.vanity.test CNAME"
echo ""

# Test NS lookup
echo "--- NS Record Tests ---"
dig @"${DNS_RESOLVER}" cloud1.test NS +short || echo "FAIL: cloud1.test NS"
dig @"${DNS_RESOLVER}" cloud2.test NS +short || echo "FAIL: cloud2.test NS"
dig @"${DNS_RESOLVER}" cloud3.test NS +short || echo "FAIL: cloud3.test NS"

echo ""
echo "=== Tests Complete ==="
