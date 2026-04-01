#!/bin/bash
# Setup WireGuard SD-WAN tunnels
# With the lima:user-v2 underlay, VMs can reach each other directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Configure WireGuard for the current SD-WAN Lima guest.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would configure WireGuard for the current SD-WAN Lima guest" "$@"

# Parent provisioners may run with xtrace enabled; turn it off here so
# WireGuard private keys and generated config do not end up in logs.
set +x

echo "=== Setting up WireGuard for $CLOUD_NAME ==="

SHARED_WG="/tmp/lima/wireguard"
mkdir -p "$SHARED_WG"

# Generate or reuse keypair for this cloud
if [ -f "$SHARED_WG/cloud${CLOUD_NUM}.key" ]; then
    WG_PRIVKEY=$(cat "$SHARED_WG/cloud${CLOUD_NUM}.key")
else
    WG_PRIVKEY=$(wg genkey)
    echo "$WG_PRIVKEY" > "$SHARED_WG/cloud${CLOUD_NUM}.key"
    chmod 600 "$SHARED_WG/cloud${CLOUD_NUM}.key"
fi
WG_PUBKEY=$(echo "$WG_PRIVKEY" | wg pubkey)

# Store public key in shared location for other VMs
echo "$WG_PUBKEY" > "$SHARED_WG/cloud${CLOUD_NUM}.pub"

UNDERLAY_HINT="$(ip -4 -o addr show | awk '$2 !~ /^(lo|br0|br1|br-aws|wg0)$/ {print $4}' | paste -sd ',')"
echo "Guest underlay interfaces: ${UNDERLAY_HINT:-unknown}"
UNDERLAY_IP="$(printf '%s\n' "${UNDERLAY_HINT}" | tr ',' '\n' | sed 's#/.*##' | sed '/^$/d' | head -1)"
if [ -z "${UNDERLAY_IP}" ]; then
    echo "ERROR: Could not determine a user-v2 underlay IP for ${CLOUD_NAME}" >&2
    exit 1
fi
echo "${UNDERLAY_IP}" > "${SHARED_WG}/cloud${CLOUD_NUM}.underlay"

# Wait for other clouds' public keys and underlay IPs (with timeout)
echo "Waiting for peer WireGuard state..."
WAIT_COUNT=0
MAX_WAIT=5
while true; do
    ALL_PRESENT=true
    for i in 1 2 3; do
        if [ "$i" != "$CLOUD_NUM" ]; then
            if [ ! -f "$SHARED_WG/cloud${i}.pub" ] || [ ! -f "$SHARED_WG/cloud${i}.underlay" ]; then
                ALL_PRESENT=false
                break
            fi
        fi
    done
    if $ALL_PRESENT; then
        break
    fi
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        echo "WARNING: Timed out waiting for peer WireGuard state. WireGuard will be configured with available peers."
        break
    fi
    sleep 2
done

# Build WireGuard config
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${TUNNEL_IP}/24
PrivateKey = ${WG_PRIVKEY}
ListenPort = 51820
EOF

for i in 1 2 3; do
    if [ "$i" = "$CLOUD_NUM" ]; then
        continue
    fi

    PEER_PUB=""
    if [ -f "$SHARED_WG/cloud${i}.pub" ]; then
        PEER_PUB=$(cat "$SHARED_WG/cloud${i}.pub")
    fi

    # Determine AllowedIPs for this peer
    case "$i" in
        1) ALLOWED_IPS="192.168.1.1/32, 172.16.10.0/24" ;;
        2) ALLOWED_IPS="192.168.1.2/32, 172.16.11.0/24" ;;
        3) ALLOWED_IPS="192.168.1.3/32, 172.16.12.0/24" ;;
    esac

    PEER_NAME="cloud${i}"
    PEER_IP=""
    if [ -f "$SHARED_WG/cloud${i}.underlay" ]; then
        PEER_IP="$(sed -n '1p' "$SHARED_WG/cloud${i}.underlay" | sed 's/[[:space:]]*$//')"
    fi
    if [ -z "$PEER_IP" ]; then
        echo "WARNING: Could not determine underlay IP for ${PEER_NAME}; skipping peer"
        continue
    fi

    if [ -n "$PEER_PUB" ]; then
        cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# ${PEER_NAME}
PublicKey = ${PEER_PUB}
AllowedIPs = ${ALLOWED_IPS}
Endpoint = ${PEER_IP}:51820
PersistentKeepalive = 25
EOF
    fi
done

chmod 600 /etc/wireguard/wg0.conf

# Bring up WireGuard
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0

# Enable WireGuard at boot
systemctl enable wg-quick@wg0

echo "=== WireGuard setup complete ==="
echo "  Tunnel IP: $TUNNEL_IP"
echo "  Underlay IP: $UNDERLAY_IP"
echo "  Public key: $WG_PUBKEY"
echo "  Peer discovery: shared user-v2 underlay state in /tmp/lima/wireguard"
