#!/bin/bash
# TLS cipher, protocol, and transport security tests
# Verifies Mozart Modern profile compliance on the sentiment compose TLS stack.
#
# Usage:
#   ./test-tls.sh [host:port] [ca-cert-path]
#   ./test-tls.sh localhost:8443 ../pki/root-ca.crt
#
# Prerequisites: openssl, curl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: ${0##*/} [--target HOST:PORT] [--ca-cert PATH] [--http-redirect-port PORT] [--dry-run] [--execute]

TLS cipher, protocol, and transport security tests for the sentiment compose TLS stack.

Positional compatibility:
  test-tls.sh [host:port] [ca-cert-path] [http-redirect-port]

Options:
  --target HOST:PORT         TLS endpoint to test
  --ca-cert PATH            local CA certificate path
  --http-redirect-port PORT HTTP port expected to redirect to HTTPS
  --dry-run                 show the selected test target and exit before network calls
  --execute                 execute the test suite
  -h, --help                show this help
EOF
}

TARGET="localhost:8443"
CA_CERT="${SCRIPT_DIR}/../pki/root-ca.crt"
HTTP_REDIRECT_PORT="8444"
positionals=()

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
    if shell_cli_handle_standard_flag usage "$1"; then
        shift
        continue
    fi

    case "$1" in
        --target)
            shift
            [[ $# -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--target" >&2; exit 1; }
            TARGET="$1"
            ;;
        --ca-cert)
            shift
            [[ $# -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--ca-cert" >&2; exit 1; }
            CA_CERT="$1"
            ;;
        --http-redirect-port)
            shift
            [[ $# -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--http-redirect-port" >&2; exit 1; }
            HTTP_REDIRECT_PORT="$1"
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
    TARGET="${positionals[0]}"
fi
if [[ "${#positionals[@]}" -ge 2 ]]; then
    CA_CERT="${positionals[1]}"
fi
if [[ "${#positionals[@]}" -ge 3 ]]; then
    HTTP_REDIRECT_PORT="${positionals[2]}"
fi
if [[ "${#positionals[@]}" -gt 3 ]]; then
    shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positionals[3]}"
    exit 2
fi

shell_cli_maybe_execute_or_preview_summary \
  usage \
  "would run sentiment TLS tests against ${TARGET} using ${CA_CERT} and redirect port ${HTTP_REDIRECT_PORT}"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }

# ---------------------------------------------------------------------------
echo "=== TLS Security Tests: $TARGET ==="
echo ""

# Sanity check
if ! command -v openssl &>/dev/null; then
    echo "ERROR: openssl not found"
    exit 1
fi
if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found"
    exit 1
fi
if [ ! -f "$CA_CERT" ]; then
    echo "ERROR: CA cert not found at $CA_CERT"
    echo "Run: cd ../pki && ./gen-certs.sh"
    exit 1
fi

# Wait for the stack to be ready (up to 30s)
echo "Waiting for $TARGET to be ready..."
for _ in $(seq 1 15); do
    if openssl s_client -connect "$TARGET" -tls1_3 -CAfile "$CA_CERT" < /dev/null 2>/dev/null | grep -q "CONNECTED"; then
        break
    fi
    sleep 2
done
echo ""

# ---------------------------------------------------------------------------
echo "--- Protocol Tests ---"

result=$(openssl s_client -connect "$TARGET" -tls1_3 -CAfile "$CA_CERT" < /dev/null 2>&1 || true)
if echo "$result" | grep -qE "Protocol[ ]*: *TLSv1\.3|New, TLSv1\.3,"; then
    pass "TLS 1.3 negotiated"
else
    fail "TLS 1.3 not negotiated (got: $(echo "$result" | grep -i protocol | head -1))"
fi

result=$(openssl s_client -connect "$TARGET" -tls1_2 -CAfile "$CA_CERT" < /dev/null 2>&1 || true)
if echo "$result" | grep -qiE "no protocols available|tlsv1 alert protocol version|handshake fail|ssl3_get_record|wrong version"; then
    pass "TLS 1.2 rejected (Mozilla Modern: TLS 1.3 only)"
else
    fail "TLS 1.2 should be rejected — server may still offer TLS 1.2"
fi

result=$(openssl s_client -connect "$TARGET" -tls1_1 -CAfile "$CA_CERT" < /dev/null 2>&1 || true)
if echo "$result" | grep -qiE "no protocols available|alert|handshake fail|ssl3_get_record|wrong version"; then
    pass "TLS 1.1 rejected"
else
    fail "TLS 1.1 should be rejected"
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Cipher Suite Tests (Mozilla Modern) ---"

result=$(openssl s_client -connect "$TARGET" -tls1_3 -CAfile "$CA_CERT" < /dev/null 2>&1 || true)
cipher=$(echo "$result" | grep -E "(^    Cipher    :|Cipher is )" | awk '{print $NF}')
if echo "$cipher" | grep -qE "TLS_AES_128_GCM_SHA256|TLS_AES_256_GCM_SHA384|TLS_CHACHA20_POLY1305_SHA256"; then
    pass "Mozilla Modern cipher in use: $cipher"
else
    fail "Expected a Mozilla Modern TLS 1.3 cipher, got: '${cipher:-unknown}'"
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Transport Tests ---"

result=$(openssl s_client -connect "$TARGET" -tls1_3 -alpn h2 -CAfile "$CA_CERT" < /dev/null 2>&1 || true)
if echo "$result" | grep -q "ALPN protocol: h2"; then
    pass "HTTP/2 negotiated via ALPN"
else
    fail "HTTP/2 not negotiated — check 'http2 on' directive in nginx config"
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Security Header Tests ---"

headers=$(curl -sk --cacert "$CA_CERT" "https://$TARGET/" -D - -o /dev/null 2>&1 || true)

hsts=$(echo "$headers" | grep -i "strict-transport-security:" | head -1)
if echo "$hsts" | grep -q "max-age=63072000"; then
    pass "HSTS max-age=63072000 (2 years)"
elif [ -n "$hsts" ]; then
    fail "HSTS present but max-age wrong (want 63072000): $hsts"
else
    fail "HSTS header missing"
fi

if echo "$headers" | grep -qi "x-frame-options:"; then
    pass "X-Frame-Options header present"
else
    fail "X-Frame-Options header missing"
fi

if echo "$headers" | grep -qi "x-content-type-options:"; then
    pass "X-Content-Type-Options header present"
else
    fail "X-Content-Type-Options header missing"
fi

if echo "$headers" | grep -qi "referrer-policy:"; then
    pass "Referrer-Policy header present"
else
    fail "Referrer-Policy header missing"
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- HTTP Redirect Test ---"

http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HTTP_REDIRECT_PORT}/" 2>/dev/null || echo "000")
if [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
    pass "HTTP → HTTPS redirect ($http_code) on port $HTTP_REDIRECT_PORT"
else
    skip "HTTP redirect returned $http_code (is port $HTTP_REDIRECT_PORT exposed?)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Certificate Tests ---"

cert_output=$(echo | openssl s_client -connect "$TARGET" -CAfile "$CA_CERT" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true)
if echo "$cert_output" | grep -q "subject"; then
    pass "Certificate presented"
    printf '           %s\n' "${cert_output//$'\n'/$'\n           '}"
else
    fail "No certificate presented"
fi

verify_output=$(echo | openssl s_client -connect "$TARGET" -CAfile "$CA_CERT" -verify_return_error 2>&1 || true)
if echo "$verify_output" | grep -q "Verify return code: 0 (ok)"; then
    pass "Certificate chain validates against local CA"
else
    code=$(echo "$verify_output" | grep "Verify return code" | head -1)
    fail "Certificate validation failed: $code"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $SKIP skipped ==="
[ "$FAIL" -eq 0 ]
