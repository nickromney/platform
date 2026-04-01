#!/bin/bash
# Cloud1 (Azure) specific provisioning
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the cloud1 guest provisioning steps for the SD-WAN Lima lab.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run cloud1 guest provisioning for the SD-WAN Lima lab" "$@"

if [ "${TRACE_PROVISIONING:-0}" = "1" ]; then
    set -x
fi

echo "=== Cloud1 (Azure) provisioning ==="

# --- Internal bridge (br0): 10.10.1.0/24 ---
ip link add br0 type bridge
ip addr add 10.10.1.4/24 dev br0    # app1 service IP
ip addr add 10.10.1.10/24 dev br0   # DNS
ip addr add 10.10.1.40/24 dev br0   # db
ip addr add 10.10.1.60/24 dev br0   # inbound gateway (nginx)
ip addr add 10.10.1.254/24 dev br0  # outbound gateway (iptables)
ip link set br0 up

# --- External bridge (br1): 172.16.10.0/24 ---
ip link add br1 type bridge
ip addr add 172.16.10.1/24 dev br1  # external VIP
ip link set br1 up

# --- Setup DNS ---
bash "$PROJECT_DIR/provision/setup-dns.sh"

# --- Setup PKI ---
bash "$PROJECT_DIR/provision/setup-pki.sh"

# --- Setup WireGuard ---
bash "$PROJECT_DIR/provision/setup-wireguard.sh"

# --- Setup nginx inbound gateway ---
bash "$PROJECT_DIR/provision/setup-nginx.sh"

# --- Setup iptables outbound gateway ---
bash "$PROJECT_DIR/provision/setup-iptables.sh"

# --- Deploy frontend ---
mkdir -p /var/www/frontend
if [ -d /tmp/lima/frontend ]; then
    cp -r /tmp/lima/frontend/* /var/www/frontend/
    echo "Frontend deployed to /var/www/frontend"
else
    echo "WARNING: /tmp/lima/frontend not found - frontend not deployed"
fi

# --- Deploy local cloud1 diagnostics API ---
mkdir -p /opt/cloud1-diagnostics
cp "$PROJECT_DIR/api/main.py" /opt/cloud1-diagnostics/main.py

cat > /etc/systemd/system/sdwan-cloud1-diagnostics.service << 'UNIT'
[Unit]
Description=SD-WAN Cloud1 Diagnostics API Service
After=network.target

[Service]
Type=simple
Environment=CLOUD_NAME=cloud1
Environment=CLOUD_IP=10.10.1.4
Environment=DNS_IP=10.10.1.10
ExecStart=/opt/app-venv/bin/uvicorn main:app --host 127.0.0.1 --port 9000
WorkingDirectory=/opt/cloud1-diagnostics
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now sdwan-cloud1-diagnostics

# --- Setup frontend nginx config ---
cp "$PROJECT_DIR/config/proxy/frontend.cloud1.conf" /etc/nginx/conf.d/frontend.conf
systemctl restart nginx

echo "=== Cloud1 (Azure) provisioning complete ==="
