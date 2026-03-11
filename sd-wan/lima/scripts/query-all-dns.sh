#!/bin/sh
# Run DNS queries from host machine against all DNS servers
# Uses the exposed ports on localhost

echo "=============================================="
echo "  DNS Query from Host Machine"
echo "=============================================="
echo ""
echo "Ports mapped:"
echo "  Cloud1 Internal: 1053"
echo "  Cloud1 External: 15353"
echo "  Cloud2 Internal: 2053"
echo "  Cloud2 External: 15354"
echo "  Cloud3 Internal: 3053"
echo "  Cloud3 External: 15355"
echo ""

echo ">>> Cloud 1 - Internal (port 1053)"
dig @127.0.0.1 -p 1053 app.cloud1.test A +short
echo ""

echo ">>> Cloud 1 - External (port 15353)"
dig @127.0.0.1 -p 15353 app.cloud1.test A +short
echo ""

echo ">>> Cloud 2 - Internal (port 2053)"
dig @127.0.0.1 -p 2053 app.cloud2.test A +short
echo ""

echo ">>> Cloud 2 - External (port 15354)"
dig @127.0.0.1 -p 15354 app.cloud2.test A +short
echo ""

echo ">>> Cloud 3 - Internal (port 3053)"
dig @127.0.0.1 -p 3053 app.cloud3.test A +short
echo ""

echo ">>> Cloud 3 - External (port 15355)"
dig @127.0.0.1 -p 15355 app.cloud3.test A +short
echo ""

echo "=============================================="
echo "  Split-Brain Demonstration"
echo "=============================================="
echo ""
echo "Same domain: app.cloud1.test"
echo ""
echo "Internal (10.x.x.x):"
dig @127.0.0.1 -p 1053 app.cloud1.test A +short
echo ""
echo "External (172.16.x.x):"
dig @127.0.0.1 -p 15353 app.cloud1.test A +short
echo ""

echo "=============================================="
echo "  CNAME Resolution"
echo "=============================================="
echo ""
echo "Same-cloud CNAME: www.cloud1.test -> app.cloud1.test"
dig @127.0.0.1 -p 1053 www.cloud1.test CNAME +short
echo ""

echo "Vanity CNAME: api1.vanity.test (points to target cloud)"
dig @127.0.0.1 -p 1053 api1.vanity.test CNAME +short
