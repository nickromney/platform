#!/bin/bash
# Subnet calculator end-to-end tests: frontend, mTLS proxy, JWT auth
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/platform-env.sh"
platform_load_env
platform_require_vars PLATFORM_DEMO_PASSWORD || exit 1

PASS=0
FAIL=0

echo "--- Frontend serving ---"
result=$(limactl shell cloud1 -- bash -c "curl -s -o /dev/null -w '%{http_code}' http://10.10.1.4:8080/" || echo "")
if [ "$result" = "200" ]; then
    echo "  PASS: Frontend serves HTTP 200"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Frontend should return 200 (got: $result)"
    FAIL=$((FAIL + 1))
fi

result=$(limactl shell cloud1 -- bash -c "curl -s http://10.10.1.4:8080/" || echo "")
if echo "$result" | grep -qi "subnet\|calculator\|html"; then
    echo "  PASS: Frontend returns HTML content"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Frontend should return HTML (got: $(echo "$result" | head -1))"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Health endpoint via API proxy (mTLS to cloud2) ---"
result=$(limactl shell cloud1 -- bash -c "curl -s http://10.10.1.4:8080/api/v1/health" || echo "")
if echo "$result" | grep -qi "healthy\|ok\|status"; then
    echo "  PASS: Health endpoint reachable via proxy"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Health endpoint should be reachable (got: $(echo "$result" | head -1))"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- JWT login via API proxy ---"
token=$(limactl shell cloud1 -- bash -c "curl -s -X POST http://10.10.1.4:8080/api/v1/auth/login -H 'Content-Type: application/x-www-form-urlencoded' --data 'username=demo&password=${PLATFORM_DEMO_PASSWORD}'" || echo "")
if echo "$token" | grep -q "access_token"; then
    echo "  PASS: JWT login returns access token"
    PASS=$((PASS + 1))
    # Extract token for subsequent requests
    JWT=$(echo "$token" | jq -r '.access_token')
else
    echo "  FAIL: JWT login should return access_token (got: $(echo "$token" | head -1))"
    FAIL=$((FAIL + 1))
    JWT=""
fi

echo ""
echo "--- Authenticated API call ---"
if [ -n "$JWT" ]; then
    result=$(limactl shell cloud1 -- bash -c "curl -s -w '\n%{http_code}' http://10.10.1.4:8080/api/v1/ipv4/subnet-info -H 'Authorization: Bearer $JWT' -H 'Content-Type: application/json' -d '{\"network\":\"10.0.0.0/24\",\"mode\":\"Standard\"}'" || echo "")
    http_code=$(echo "$result" | tail -1)
    body=$(echo "$result" | sed '$d')
    if [ "$http_code" = "200" ]; then
        echo "  PASS: Authenticated subnet-info returns 200"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Authenticated request should return 200 (got: $http_code, body: $(echo "$body" | head -1))"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SKIP: No JWT token available (login failed)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Unauthenticated API rejection ---"
result=$(limactl shell cloud1 -- bash -c "curl -s -o /dev/null -w '%{http_code}' http://10.10.1.4:8080/api/v1/ipv4/subnet-info -H 'Content-Type: application/json' -d '{\"network\":\"10.0.0.0/24\",\"mode\":\"Standard\"}'" || echo "")
if [ "$result" = "401" ] || [ "$result" = "403" ]; then
    echo "  PASS: Unauthenticated request rejected ($result)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Unauthenticated request should be rejected (got: $result)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Subnet Calculator Tests: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
