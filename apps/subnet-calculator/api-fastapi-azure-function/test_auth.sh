#!/usr/bin/env bash
#
# Integration test script for API authentication
# Tests AUTH_METHOD=none and AUTH_METHOD=api_key modes
#
# Usage:
#   ./test_auth.sh [BASE_URL]
#
# Examples:
#   ./test_auth.sh                              # Test local func start (port 7071)
#   ./test_auth.sh http://localhost:8080        # Test Docker container
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat << EOF
Usage: $0 [--base-url URL] [--dry-run] [--execute]

Integration test script for API authentication.

Options:
    --base-url URL  Override the API base URL (default: http://localhost:7071)
    --dry-run       Show the selected API target and exit before HTTP calls
    --execute       Execute the authentication test suite
    --help, -h      Show this help message

Positional compatibility:
    $0 [BASE_URL]

Examples:
    $0 --execute
    $0 --base-url http://localhost:8080 --execute
EOF
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default to local Azure Functions
BASE_URL="http://localhost:7071"
dry_run=0
positionals=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            shift
            [[ $# -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--base-url" >&2; exit 1; }
            BASE_URL="$1"
            ;;
        --dry-run)
            dry_run=1
            ;;
        --execute)
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                positionals+=("$1")
                shift
            done
            break
            ;;
        -*)
            shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
            exit 2
            ;;
        *)
            positionals+=("$1")
            ;;
    esac
    shift
done

if [[ "${#positionals[@]}" -ge 1 ]]; then
    BASE_URL="${positionals[0]}"
fi
if [[ "${#positionals[@]}" -gt 1 ]]; then
    shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positionals[1]}"
    exit 2
fi

if [[ "${dry_run}" -eq 1 ]]; then
    shell_cli_print_dry_run_summary "would run authentication integration tests against ${BASE_URL}"
    exit 0
fi

HEALTH_URL="${BASE_URL}/api/v1/health"

echo "==========================================="
echo "API Authentication Integration Tests"
echo "==========================================="
echo "Base URL: ${BASE_URL}"
echo ""

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper function
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="$3"
    local headers="${4:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    echo -n "Test ${TESTS_RUN}: ${name}... "

    if [ -n "$headers" ]; then
        actual_status=$(curl -s -o /dev/null -w "%{http_code}" -H "$headers" "$url")
    else
        actual_status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    fi

    if [ "$actual_status" -eq "$expected_status" ]; then
        echo -e "${GREEN}PASS${NC} (${actual_status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected ${expected_status}, got ${actual_status})"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test with POST requests
test_endpoint_post() {
    local name="$1"
    local url="$2"
    local expected_status="$3"
    local data="$4"
    local headers="${5:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    echo -n "Test ${TESTS_RUN}: ${name}... "

    if [ -n "$headers" ]; then
        actual_status=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "$headers" \
            -d "$data" \
            "$url")
    else
        actual_status=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$url")
    fi

    if [ "$actual_status" -eq "$expected_status" ]; then
        echo -e "${GREEN}PASS${NC} (${actual_status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected ${expected_status}, got ${actual_status})"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "==========================================="
echo "Test Group 1: No Authentication Mode"
echo "==========================================="
echo "Expects: AUTH_METHOD=none (default)"
echo ""

test_endpoint "Health check without auth" "$HEALTH_URL" 200
test_endpoint "Health check with API key (should be ignored)" "$HEALTH_URL" 200 "X-API-Key: any-key"
test_endpoint_post "Validate endpoint without auth" "${BASE_URL}/api/v1/ipv4/validate" 200 '{"address":"192.168.1.1"}'

echo ""
echo "==========================================="
echo "Test Group 2: API Key Authentication"
echo "==========================================="
echo "Instructions:"
echo "1. Set environment variables:"
echo "   export AUTH_METHOD=api_key"
echo "   export API_KEYS=test-key-123,another-key"
echo "2. Restart the API"
echo "3. Run this script again"
echo ""
echo -e "${YELLOW}Skipping API key tests (set AUTH_METHOD=api_key to enable)${NC}"
echo ""

# Uncomment these when testing with AUTH_METHOD=api_key
# test_endpoint "Missing API key returns 401" "$HEALTH_URL" 401
# test_endpoint "Invalid API key returns 401" "$HEALTH_URL" 401 "X-API-Key: invalid-key"
# test_endpoint "Valid API key returns 200" "$HEALTH_URL" 200 "X-API-Key: test-key-123"
# test_endpoint "Second valid key works" "$HEALTH_URL" 200 "X-API-Key: another-key"
# test_endpoint_post "Validate with valid key" "${BASE_URL}/api/v1/ipv4/validate" 200 '{"address":"192.168.1.1"}' "X-API-Key: test-key-123"
# test_endpoint_post "Validate without key returns 401" "${BASE_URL}/api/v1/ipv4/validate" 401 '{"address":"192.168.1.1"}'

echo "==========================================="
echo "Test Results"
echo "==========================================="
echo "Total tests run: ${TESTS_RUN}"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi
