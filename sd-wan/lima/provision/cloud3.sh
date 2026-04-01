#!/bin/bash
# Cloud3 (AWS) specific provisioning
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the cloud3 guest provisioning steps for the SD-WAN Lima lab.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run cloud3 guest provisioning for the SD-WAN Lima lab" "$@"

if [ "${TRACE_PROVISIONING:-0}" = "1" ]; then
    set -x
fi

echo "=== Cloud3 (AWS) provisioning ==="

# --- Internal bridge (br0): 10.10.1.0/24 (gateway layer, overlaps) ---
ip link add br0 type bridge
ip addr add 10.10.1.60/24 dev br0   # inbound gateway (nginx)
ip addr add 10.10.1.254/24 dev br0  # outbound gateway (iptables)
ip link set br0 up

# --- AWS VPC bridge (br-aws): 172.31.1.0/24 ---
ip link add br-aws type bridge
ip addr add 172.31.1.1/24 dev br-aws   # app2 service IP
ip addr add 172.31.1.10/24 dev br-aws  # DNS
ip link set br-aws up

# --- External bridge (br1): 172.16.12.0/24 ---
ip link add br1 type bridge
ip addr add 172.16.12.3/24 dev br1  # external VIP
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

# --- Deploy FastAPI app ---
cp "$PROJECT_DIR/api/main.py" /opt/app/main.py

cat > /etc/systemd/system/sdwan-app.service << 'UNIT'
[Unit]
Description=SD-WAN API Service
After=network.target

[Service]
Type=simple
Environment=CLOUD_NAME=Cloud3-AWS
Environment=CLOUD_IP=172.31.1.1
ExecStart=/opt/app-venv/bin/uvicorn main:app --host 172.31.1.1 --port 8000
WorkingDirectory=/opt/app
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now sdwan-app

echo "=== Cloud3 (AWS) provisioning complete ==="
