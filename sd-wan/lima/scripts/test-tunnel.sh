#!/bin/sh
# Tunnel Connectivity Test Script
# Demonstrates SD-WAN connectivity scenarios

apk add --no-cache bind-tools iproute2 curl >/dev/null 2>&1

echo "=============================================="
echo "  SD-WAN Connectivity Demonstration"
echo "=============================================="
echo ""
echo "Scenarios:"
echo "1. On-Prem -> AWS (direct)"
echo "2. On-Prem -> Azure (direct)"
echo "3. On-Prem -> Azure via Tunnel (SD-WAN)"
echo ""

echo ">>> SCENARIO 1: On-Prem (cloud1) -> AWS (cloud2)"
echo "    Source: 10.1.0.100 (on-prem client)"
echo "    Target: 10.2.0.20 (app in AWS)"
echo ""

# Test if we can reach cloud2 from cloud1
echo "    Testing ping..."
ping -c 1 -W 2 10.2.0.20 >/dev/null 2>&1 && echo "    Result: REACHABLE (direct)" || echo "    Result: NOT REACHABLE"
echo ""

echo ">>> SCENARIO 2: On-Prem (cloud1) -> Azure (cloud3)"
echo "    Source: 10.1.0.100 (on-prem client)"
echo "    Target: 10.3.0.20 (app in Azure)"
echo ""

echo "    Testing ping..."
ping -c 1 -W 2 10.3.0.20 >/dev/null 2>&1 && echo "    Result: REACHABLE (direct)" || echo "    Result: NOT REACHABLE"
echo ""

echo ">>> SCENARIO 3: On-Prem -> Azure via Tunnel"
echo "    Using tunnel gateway at 10.1.0.200"
echo ""

# Set up route through tunnel gateway
echo "    Adding route via tunnel gateway..."
ip route add 10.3.0.0/24 via 10.1.0.200 2>/dev/null && echo "    Route added" || echo "    Route exists"

echo "    Testing ping via tunnel..."
ping -c 1 -W 2 10.3.0.20 >/dev/null 2>&1 && echo "    Result: REACHABLE (tunnel)" || echo "    Result: NOT REACHABLE"
echo ""

echo ">>> DNS Resolution Tests"
echo ""

echo "    On-Prem resolving AWS app..."
dig @10.1.0.10 app.cloud2.test A +short
echo ""

echo "    On-Prem resolving Azure app..."
dig @10.1.0.10 app.cloud3.test A +short
echo ""

echo "=============================================="
echo "  Summary"
echo ""
echo "With SD-WAN:"
echo "- Direct tunnel between on-prem and AWS works"
echo "- Tunnel gateway enables on-prem to reach Azure"
echo "- DNS returns RFC1918 for internal/overlay access"
echo ""
