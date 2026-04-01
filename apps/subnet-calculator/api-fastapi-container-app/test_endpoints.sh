#!/bin/bash
# test_endpoints.sh - Container App API endpoint testing script
# Tests all endpoints with JWT authentication using curl

set -e

# Show help message
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Test the Container App subnet calculator API endpoints with JWT authentication.

OPTIONS:
    --base-url URL  Override the API base URL
    --detailed      Run all endpoints with full command output
    --dry-run       Show the selected API target and exit before HTTP calls
    --execute       Execute the endpoint test suite
    --help, -h      Show this help message

EXAMPLES:
    $0 --execute                      # Smoke test on local API (port 8090)
    $0 --detailed --execute           # All endpoints on local API (port 8090)
    $0 --base-url http://localhost:8090/api --execute

REQUIREMENTS:
    - API must be running before executing tests
    - curl must be installed
    - API must have JWT authentication enabled

Start the API with:
    podman-compose up api-fastapi-container-app    # Container App only
    podman-compose up                               # All services

AUTHENTICATION:
    - Uses demo@dev.test:demo-password credentials
    - Automatically gets JWT token before testing

EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

# Parse arguments
DETAILED=false
BASE_URL=""
positionals=()

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
    if shell_cli_handle_standard_flag show_help "$1"; then
        shift
        continue
    fi

    case $1 in
        --base-url)
            shift
            [[ $# -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--base-url" >&2; exit 1; }
            BASE_URL="$1"
            ;;
        --detailed)
            DETAILED=true
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

# Set default if not specified
if [ -z "$BASE_URL" ]; then
    BASE_URL="http://localhost:8090/api"
fi

if [ "$DETAILED" = true ]; then
    shell_cli_maybe_execute_or_preview_summary \
      show_help \
      "would run detailed Container App endpoint tests against ${BASE_URL}"
else
    shell_cli_maybe_execute_or_preview_summary \
      show_help \
      "would run smoke Container App endpoint tests against ${BASE_URL}"
fi

echo "Using curl for HTTP requests"
echo ""
echo "========================================="
if [ "$DETAILED" = true ]; then
    echo "Detailed Test: $BASE_URL"
else
    echo "Smoke Test: $BASE_URL"
fi
echo "========================================="

# Test connectivity first
echo ""
echo "Checking API connectivity..."
if ! curl -sf "$BASE_URL/v1/health" > /dev/null 2>&1; then
    echo ""
    echo "ERROR: Cannot connect to API at $BASE_URL"
    echo ""
    echo "Make sure the API is running:"
    echo "  podman-compose up api-fastapi-container-app"
    echo ""
    exit 1
fi

echo "✓ API is reachable"

# Get JWT token
echo "Getting JWT token..."
if ! TOKEN_RESPONSE=$(curl -sf -X POST "$BASE_URL/v1/auth/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=demo@dev.test&password=demo-password" 2>/dev/null); then
    echo "ERROR: Failed to get JWT token"
    exit 1
fi

# Extract token (prefer jq if available, fallback to grep/cut)
if command -v jq &> /dev/null; then
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
else
    TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
fi

if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not extract token from response"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "✓ JWT token obtained"
echo ""

# Helper function for authenticated POST requests
auth_post() {
    local endpoint=$1
    local data=$2

    if [ "$DETAILED" = true ]; then
        echo "$ curl -X POST $BASE_URL/$endpoint -H \"Authorization: Bearer \$TOKEN\" -d '$data'"
    fi

    curl -sf -X POST "$BASE_URL/$endpoint" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "$data"
}

# Helper function for GET requests
get_request() {
    local endpoint=$1

    if [ "$DETAILED" = true ]; then
        echo "$ curl $BASE_URL/$endpoint"
    fi

    curl -sf "$BASE_URL/$endpoint"
}

# Run smoke test or detailed test
if [ "$DETAILED" = true ]; then
    echo "Running detailed test (all endpoints)..."
    echo ""

    # Test 1: Health Check
    echo "1. Health Check"
    echo "---"
    get_request "v1/health"
    echo ""
    echo ""

    # Test 2: Validate IPv4 Address
    echo "2. Validate IPv4 Address"
    echo "---"
    auth_post "v1/ipv4/validate" '{"address":"192.168.1.1"}'
    echo ""
    echo ""

    # Test 3: Validate IPv4 Network (CIDR)
    echo "3. Validate IPv4 Network (CIDR)"
    echo "---"
    auth_post "v1/ipv4/validate" '{"address":"192.168.1.0/24"}'
    echo ""
    echo ""

    # Test 4: Validate IPv6 Address
    echo "4. Validate IPv6 Address"
    echo "---"
    auth_post "v1/ipv4/validate" '{"address":"2001:db8::1"}'
    echo ""
    echo ""

    # Test 5: Check RFC1918 Private Address (192.168.x)
    echo "5. Check RFC1918 Private Address (192.168.x)"
    echo "---"
    auth_post "v1/ipv4/check-private" '{"address":"192.168.1.1"}'
    echo ""
    echo ""

    # Test 6: Check RFC1918 Private Address (10.x)
    echo "6. Check RFC1918 Private Address (10.x)"
    echo "---"
    auth_post "v1/ipv4/check-private" '{"address":"10.50.100.200"}'
    echo ""
    echo ""

    # Test 7: Check RFC6598 Shared Address Space
    echo "7. Check RFC6598 Shared Address Space"
    echo "---"
    auth_post "v1/ipv4/check-private" '{"address":"100.64.1.1"}'
    echo ""
    echo ""

    # Test 8: Check Public Address
    echo "8. Check Public Address (not RFC1918/RFC6598)"
    echo "---"
    auth_post "v1/ipv4/check-private" '{"address":"8.8.8.8"}'
    echo ""
    echo ""

    # Test 9: Check Cloudflare IPv4 Range
    echo "9. Check Cloudflare IPv4 Range"
    echo "---"
    auth_post "v1/ipv4/check-cloudflare" '{"address":"104.16.1.1"}'
    echo ""
    echo ""

    # Test 10: Check Cloudflare IPv6 Range
    echo "10. Check Cloudflare IPv6 Range"
    echo "---"
    auth_post "v1/ipv4/check-cloudflare" '{"address":"2606:4700::1"}'
    echo ""
    echo ""

    # Test 11: Check Non-Cloudflare Address
    echo "11. Check Non-Cloudflare Address"
    echo "---"
    auth_post "v1/ipv4/check-cloudflare" '{"address":"8.8.8.8"}'
    echo ""
    echo ""

    # Test 12: Subnet Info - Azure Mode
    echo "12. Subnet Info - Azure Mode (default)"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"192.168.1.0/24","mode":"Azure"}'
    echo ""
    echo ""

    # Test 13: Subnet Info - AWS Mode
    echo "13. Subnet Info - AWS Mode"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"10.0.1.0/24","mode":"AWS"}'
    echo ""
    echo ""

    # Test 14: Subnet Info - OCI Mode
    echo "14. Subnet Info - OCI Mode"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"172.16.0.0/24","mode":"OCI"}'
    echo ""
    echo ""

    # Test 15: Subnet Info - Standard Mode
    echo "15. Subnet Info - Standard Mode"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"10.0.0.0/24","mode":"Standard"}'
    echo ""
    echo ""

    # Test 16: Subnet Info - /31 Point-to-Point
    echo "16. Subnet Info - /31 Point-to-Point"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"10.0.0.0/31","mode":"Standard"}'
    echo ""
    echo ""

    # Test 17: Subnet Info - /32 Single Host
    echo "17. Subnet Info - /32 Single Host"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"10.0.0.5/32","mode":"Standard"}'
    echo ""
    echo ""

    # Test 18: IPv6 Subnet Info
    echo "18. IPv6 Subnet Info"
    echo "---"
    auth_post "v1/ipv6/subnet-info" '{"network":"2001:db8::/64"}'
    echo ""
    echo ""

    echo "========================================="
    echo "All tests completed!"
    echo "========================================="
else
    echo "Running smoke test (use --detailed for all endpoints)..."
    echo ""

    # Smoke test - key endpoints
    echo "1. Health Check"
    echo "---"
    get_request "v1/health"
    echo ""

    echo "2. Validate IPv4 Address"
    echo "---"
    auth_post "v1/ipv4/validate" '{"address":"192.168.1.1"}'
    echo ""

    echo "3. Check RFC1918 Private Address"
    echo "---"
    auth_post "v1/ipv4/check-private" '{"address":"192.168.1.1"}'
    echo ""

    echo "4. Check Cloudflare Range"
    echo "---"
    auth_post "v1/ipv4/check-cloudflare" '{"address":"104.16.1.1"}'
    echo ""

    echo "5. Subnet Info (Azure Mode)"
    echo "---"
    auth_post "v1/ipv4/subnet-info" '{"network":"192.168.1.0/24","mode":"Azure"}'
    echo ""

    echo "6. IPv6 Subnet Info"
    echo "---"
    auth_post "v1/ipv6/subnet-info" '{"network":"2001:db8::/64"}'
    echo ""

    echo "========================================="
    echo "✓ Smoke test passed!"
    echo "Run with --detailed to test all endpoints"
    echo "========================================="
fi
