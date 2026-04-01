#!/bin/bash
# Setup CoreDNS for each cloud
# Reads CLOUD_NUM, DNS_IP, PROJECT_DIR from environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Configure CoreDNS for the current SD-WAN Lima guest.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would configure CoreDNS for the current SD-WAN Lima guest" "$@"

if [ "${TRACE_PROVISIONING:-0}" = "1" ]; then
    set -x
fi

echo "=== Setting up CoreDNS for $CLOUD_NAME ==="

# Copy Corefile from config
cp "$PROJECT_DIR/config/$CLOUD_NAME/internal.Corefile" /etc/coredns/Corefile

# Create systemd service for CoreDNS
# Bind to the DNS IP on the internal bridge
if [ "$CLOUD_NUM" = "3" ]; then
    LISTEN_IP="172.31.1.10"
else
    LISTEN_IP="10.10.1.10"
fi

cat > /etc/systemd/system/coredns.service << EOF
[Unit]
Description=CoreDNS DNS Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/coredns -conf /etc/coredns/Corefile -dns.port 53
Restart=always
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

# Disable systemd-resolved to free port 53
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true

# Point system resolver at our CoreDNS
cat > /etc/resolv.conf << EOF
nameserver $LISTEN_IP
search $CLOUD_NAME.test
EOF

systemctl daemon-reload
systemctl enable --now coredns

echo "=== CoreDNS setup complete ==="
