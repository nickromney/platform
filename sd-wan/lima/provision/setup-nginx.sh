#!/bin/bash
# Setup nginx inbound gateway with TLS + mTLS
# Reads CLOUD_NUM, CLOUD_NAME, INBOUND_IP, EXTERNAL_VIP, PROJECT_DIR from environment
set -euo pipefail
if [ "${TRACE_PROVISIONING:-0}" = "1" ]; then
    set -x
fi

echo "=== Setting up nginx inbound gateway for $CLOUD_NAME ==="

# Remove default nginx config
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/conf.d/default.conf

# Copy cloud-specific inbound config
cp "$PROJECT_DIR/config/gateway/inbound.${CLOUD_NAME}.conf" /etc/nginx/conf.d/inbound.conf

# Test nginx config
nginx -t

# Enable and restart nginx with updated config
systemctl enable nginx
systemctl restart nginx

echo "=== Nginx inbound gateway setup complete ==="
