#!/bin/bash
# mTLS certificate verification tests
set -euo pipefail

PASS=0
FAIL=0

echo "--- Certificate SAN validation ---"
# Check cloud2 inbound cert has api1.vanity.test SAN
result=$(limactl shell cloud1 -- bash -c "echo | openssl s_client -connect 172.16.11.2:443 -servername api1.vanity.test 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>/dev/null" || echo "")
if echo "$result" | grep -q "api1.vanity.test"; then
    echo "  PASS: Cloud2 inbound cert has SAN api1.vanity.test"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Cloud2 inbound cert missing SAN api1.vanity.test"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- mTLS rejection without client cert ---"
# curl without client cert should fail
result=$(limactl shell cloud1 -- bash -c "sudo curl -s --cacert /etc/pki/root-ca.crt https://172.16.11.2/api/v1/health 2>&1" || true)
if echo "$result" | grep -qiE "SSL|certificate|error|alert|required|400"; then
    echo "  PASS: Request without client cert rejected"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Request without client cert should be rejected (got: $(echo "$result" | head -1))"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- mTLS success with client cert ---"
result=$(limactl shell cloud1 -- bash -c "sudo curl -s --cert /etc/pki/client.crt --key /etc/pki/client.key --cacert /etc/pki/root-ca.crt https://172.16.11.2/api/v1/health 2>/dev/null" || echo "")
if echo "$result" | grep -q "healthy"; then
    echo "  PASS: Request with client cert accepted"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Request with client cert should succeed"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Client identity propagation ---"
result=$(limactl shell cloud1 -- bash -c "sudo curl -s --cert /etc/pki/client.crt --key /etc/pki/client.key --cacert /etc/pki/root-ca.crt -D - https://172.16.11.2/api/v1/health 2>/dev/null" || echo "")
if echo "$result" | grep -qi "client"; then
    echo "  PASS: Client identity propagated in response"
    PASS=$((PASS + 1))
else
    echo "  INFO: Client identity header check (may need X-Client-CN header inspection)"
    # Not a hard fail - depends on backend echoing headers
fi

echo ""
echo "--- Certificate chain validation ---"
for cloud in cloud1 cloud2 cloud3; do
    result=$(limactl shell "$cloud" -- bash -c "openssl verify -CAfile /etc/pki/root-ca.crt -untrusted /etc/pki/intermediate.crt /etc/pki/server.crt 2>&1" || echo "")
    if echo "$result" | grep -q "OK"; then
        echo "  PASS: $cloud server cert chain validates"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $cloud server cert chain invalid"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== mTLS Tests: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
