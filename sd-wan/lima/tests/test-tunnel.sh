#!/bin/bash
# WireGuard tunnel connectivity tests
set -euo pipefail

PASS=0
FAIL=0

check_ping() {
    local desc="$1"
    local cloud="$2"
    local target="$3"

    if limactl shell "$cloud" -- sudo ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- WireGuard mesh connectivity ---"
check_ping "cloud1 -> cloud2 tunnel (192.168.1.2)" cloud1 192.168.1.2
check_ping "cloud1 -> cloud3 tunnel (192.168.1.3)" cloud1 192.168.1.3
check_ping "cloud2 -> cloud1 tunnel (192.168.1.1)" cloud2 192.168.1.1
check_ping "cloud2 -> cloud3 tunnel (192.168.1.3)" cloud2 192.168.1.3
check_ping "cloud3 -> cloud1 tunnel (192.168.1.1)" cloud3 192.168.1.1
check_ping "cloud3 -> cloud2 tunnel (192.168.1.2)" cloud3 192.168.1.2

echo ""
echo "--- WireGuard handshakes ---"
for cloud in cloud1 cloud2 cloud3; do
    echo "  $cloud:"
    limactl shell "$cloud" -- sudo wg show wg0 latest-handshakes 2>/dev/null | while read -r key ts; do
        if [ -n "$ts" ] && [ "$ts" != "0" ]; then
            echo "    Peer $key: handshake $(( $(date +%s) - ts ))s ago"
            PASS=$((PASS + 1))
        fi
    done
done

echo ""
echo "--- VIP reachability via tunnel ---"
check_ping "cloud1 -> cloud2 VIP (172.16.11.2)" cloud1 172.16.11.2
check_ping "cloud1 -> cloud3 VIP (172.16.12.3)" cloud1 172.16.12.3
check_ping "cloud2 -> cloud1 VIP (172.16.10.1)" cloud2 172.16.10.1
check_ping "cloud2 -> cloud3 VIP (172.16.12.3)" cloud2 172.16.12.3
check_ping "cloud3 -> cloud1 VIP (172.16.10.1)" cloud3 172.16.10.1
check_ping "cloud3 -> cloud2 VIP (172.16.11.2)" cloud3 172.16.11.2

echo ""
echo "=== Tunnel Tests: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
