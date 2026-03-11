#!/bin/bash
# Setup CoreDNS for each cloud
# Reads CLOUD_NUM, DNS_IP, PROJECT_DIR from environment
set -eux

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
