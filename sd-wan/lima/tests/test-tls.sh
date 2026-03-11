#!/bin/bash
# TLS protocol and cipher security tests for lima inbound gateways
# Verifies Mozilla Modern profile compliance after the TLS 1.3 upgrade.
#
# Run from the host (requires limactl in PATH).
# Usage: ./test-tls.sh
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Helper: run openssl s_client from inside a lima VM
# Usage: s_client_from <vm> <target-ip:port> [extra openssl flags]
# ---------------------------------------------------------------------------
s_client_from() {
    local vm="$1"
    local target="$2"
    shift 2
    limactl shell "$vm" -- bash -c \
        "echo | sudo openssl s_client -connect $target $* 2>&1 || true"
}

extract_cipher() {
    local input="$1"
    printf '%s\n' "$input" | grep -E "(^    Cipher    :|Cipher is )" | awk '{print $NF}' | tail -n 1 || true
}

# ---------------------------------------------------------------------------
echo "=== TLS Protocol Tests (Mozilla Modern: TLS 1.3 only) ==="
echo ""

# --- Cloud1 inbound ---
echo "--- Cloud1 inbound (10.10.1.60:8443 listener) ---"

result=$(s_client_from cloud1 "10.10.1.60:8443" \
    "-tls1_3 -servername inbound.cloud1.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")
if echo "$result" | grep -qE "Protocol[ ]*: *TLSv1\.3|New, TLSv1\.3,"; then
    pass "Cloud1: TLS 1.3 negotiated"
else
    fail "Cloud1: TLS 1.3 not negotiated"
fi

result=$(s_client_from cloud1 "10.10.1.60:8443" \
    "-tls1_2 -servername inbound.cloud1.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")
if echo "$result" | grep -qiE "no protocols available|alert protocol version|handshake fail|wrong version"; then
    pass "Cloud1: TLS 1.2 rejected"
else
    fail "Cloud1: TLS 1.2 should be rejected (Mozilla Modern = TLS 1.3 only)"
fi

cipher=$(extract_cipher "$(s_client_from cloud1 "10.10.1.60:8443" \
    "-tls1_3 -servername inbound.cloud1.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")")
if echo "$cipher" | grep -qE "TLS_AES_128_GCM_SHA256|TLS_AES_256_GCM_SHA384|TLS_CHACHA20_POLY1305_SHA256"; then
    pass "Cloud1: Mozilla Modern cipher in use: $cipher"
else
    fail "Cloud1: Non-modern cipher: ${cipher:-unknown}"
fi

# --- Cloud2 inbound ---
echo ""
echo "--- Cloud2 inbound (172.16.11.2:443) ---"

result=$(s_client_from cloud1 "172.16.11.2:443" \
    "-tls1_3 -servername api1.vanity.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")
if echo "$result" | grep -qE "Protocol[ ]*: *TLSv1\.3|New, TLSv1\.3,"; then
    pass "Cloud2: TLS 1.3 negotiated"
else
    fail "Cloud2: TLS 1.3 not negotiated"
fi

result=$(s_client_from cloud1 "172.16.11.2:443" \
    "-tls1_2 -servername api1.vanity.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")
if echo "$result" | grep -qiE "no protocols available|alert protocol version|handshake fail|wrong version"; then
    pass "Cloud2: TLS 1.2 rejected"
else
    fail "Cloud2: TLS 1.2 should be rejected"
fi

cipher=$(extract_cipher "$(s_client_from cloud1 "172.16.11.2:443" \
    "-tls1_3 -servername api1.vanity.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")")
if echo "$cipher" | grep -qE "TLS_AES_128_GCM_SHA256|TLS_AES_256_GCM_SHA384|TLS_CHACHA20_POLY1305_SHA256"; then
    pass "Cloud2: Mozilla Modern cipher in use: $cipher"
else
    fail "Cloud2: Non-modern cipher: ${cipher:-unknown}"
fi

# --- Cloud3 inbound ---
echo ""
echo "--- Cloud3 inbound (172.16.12.3:443) ---"

result=$(s_client_from cloud1 "172.16.12.3:443" \
    "-tls1_3 -servername inbound.cloud3.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")
if echo "$result" | grep -qE "Protocol[ ]*: *TLSv1\.3|New, TLSv1\.3,"; then
    pass "Cloud3: TLS 1.3 negotiated"
else
    fail "Cloud3: TLS 1.3 not negotiated"
fi

result=$(s_client_from cloud1 "172.16.12.3:443" \
    "-tls1_2 -servername inbound.cloud3.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")
if echo "$result" | grep -qiE "no protocols available|alert protocol version|handshake fail|wrong version"; then
    pass "Cloud3: TLS 1.2 rejected"
else
    fail "Cloud3: TLS 1.2 should be rejected"
fi

cipher=$(extract_cipher "$(s_client_from cloud1 "172.16.12.3:443" \
    "-tls1_3 -servername inbound.cloud3.test -CAfile /etc/pki/root-ca.crt \
     -cert /etc/pki/client.crt -key /etc/pki/client.key")")
if echo "$cipher" | grep -qE "TLS_AES_128_GCM_SHA256|TLS_AES_256_GCM_SHA384|TLS_CHACHA20_POLY1305_SHA256"; then
    pass "Cloud3: Mozilla Modern cipher in use: $cipher"
else
    fail "Cloud3: Non-modern cipher: ${cipher:-unknown}"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== HSTS Header Tests ==="
echo ""

for cloud_target in \
    "cloud1|10.10.1.60|8443|inbound.cloud1.test" \
    "cloud1|172.16.11.2|443|api1.vanity.test" \
    "cloud1|172.16.12.3|443|inbound.cloud3.test"; do
    IFS='|' read -r vm ip port sni <<<"$cloud_target"

    hsts=$(limactl shell "$vm" -- bash -c \
        "sudo curl -sk --cacert /etc/pki/root-ca.crt \
         --cert /etc/pki/client.crt --key /etc/pki/client.key \
         --resolve $sni:$port:$ip \
         -D - https://$sni:$port/ -o /dev/null 2>/dev/null \
         | grep -i strict-transport-security || true")
    if echo "$hsts" | grep -q "max-age=63072000"; then
        pass "$sni: HSTS max-age=63072000 present"
    elif [ -n "$hsts" ]; then
        fail "$sni: HSTS present but wrong max-age: $hsts"
    else
        fail "$sni: HSTS header missing"
    fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== TLS Tests: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
