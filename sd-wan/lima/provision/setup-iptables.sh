#!/bin/bash
# Setup iptables outbound gateway (egress firewall)
# Reads CLOUD_NUM, CLOUD_NAME, PROJECT_DIR from environment
set -euo pipefail
if [ "${TRACE_PROVISIONING:-0}" = "1" ]; then
    set -x
fi

echo "=== Setting up iptables outbound gateway for $CLOUD_NAME ==="

# Load cloud-specific egress rules
RULES_FILE="$PROJECT_DIR/config/$CLOUD_NAME/iptables-egress.rules"

if [ -f "$RULES_FILE" ]; then
    bash "$RULES_FILE"
else
    echo "No custom rules file, applying defaults..."

    # Default policy: drop forwarded traffic
    iptables -P FORWARD DROP

    # Allow established/related connections
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow internal → tunnel overlay (SD-WAN)
    iptables -A FORWARD -s 10.10.1.0/24 -d 192.168.1.0/24 -j ACCEPT

    # Allow internal → external VIPs of other clouds
    case "$CLOUD_NUM" in
        1)
            iptables -A FORWARD -s 10.10.1.0/24 -d 172.16.11.0/24 -j ACCEPT
            iptables -A FORWARD -s 10.10.1.0/24 -d 172.16.12.0/24 -j ACCEPT
            ;;
        2)
            iptables -A FORWARD -s 10.10.1.0/24 -d 172.16.10.0/24 -j ACCEPT
            iptables -A FORWARD -s 10.10.1.0/24 -d 172.16.12.0/24 -j ACCEPT
            ;;
        3)
            # Cloud3 uses 172.31.1.0/24 internally
            iptables -A FORWARD -s 172.31.1.0/24 -d 192.168.1.0/24 -j ACCEPT
            iptables -A FORWARD -s 172.31.1.0/24 -d 172.16.10.0/24 -j ACCEPT
            iptables -A FORWARD -s 172.31.1.0/24 -d 172.16.11.0/24 -j ACCEPT
            ;;
    esac

    # SNAT outbound traffic going through WireGuard
    iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -o wg0 -j MASQUERADE
    if [ "$CLOUD_NUM" = "3" ]; then
        iptables -t nat -A POSTROUTING -s 172.31.1.0/24 -o wg0 -j MASQUERADE
    fi

    # DNAT inbound VIP traffic to nginx
    iptables -t nat -A PREROUTING -d "$EXTERNAL_VIP" -p tcp --dport 80 \
        -j DNAT --to-destination 10.10.1.60:8080
    iptables -t nat -A PREROUTING -d "$EXTERNAL_VIP" -p tcp --dport 443 \
        -j DNAT --to-destination 10.10.1.60:8443

    # Log + drop everything else
    iptables -A FORWARD -j LOG --log-prefix "EGRESS-DENIED: " --log-level 4
    iptables -A FORWARD -j DROP
fi

# Save rules for persistence
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

echo "=== Iptables outbound gateway setup complete ==="
