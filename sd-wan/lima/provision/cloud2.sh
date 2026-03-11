#!/bin/bash
# Cloud2 (on-prem) specific provisioning
set -eux

echo "=== Cloud2 (on-prem) provisioning ==="

# --- Internal bridge (br0): 10.10.1.0/24 (SAME as cloud1 - overlapping!) ---
ip link add br0 type bridge
ip addr add 10.10.1.4/24 dev br0    # api1 service IP (same as cloud1's app1!)
ip addr add 10.10.1.10/24 dev br0   # DNS
ip addr add 10.10.1.60/24 dev br0   # inbound gateway (nginx)
ip addr add 10.10.1.254/24 dev br0  # outbound gateway (iptables)
ip link set br0 up

# --- External bridge (br1): 172.16.11.0/24 ---
ip link add br1 type bridge
ip addr add 172.16.11.2/24 dev br1  # external VIP
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

# --- Deploy subnet-calculator API ---
# Find the repo root (PROJECT_DIR is sd-wan/lima)
REPO_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
cp -r "$REPO_ROOT/apps/subnet-calculator/api-fastapi-container-app/app" /opt/app/app

cat > /etc/systemd/system/sdwan-app.service << 'UNIT'
[Unit]
Description=Subnet Calculator API Service
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/default/sdwan-app
ExecStart=/opt/app-venv/bin/uvicorn app.main:app --host 10.10.1.4 --port 8000
WorkingDirectory=/opt/app
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

# Generate hashed password for demo user
DEMO_HASH=$(/opt/app-venv/bin/python3 -c "from pwdlib import PasswordHash; from pwdlib.hashers.argon2 import Argon2Hasher; h = PasswordHash((Argon2Hasher(),)); print(h.hash('password123'))")

# Write environment file (avoids systemd quoting issues)
cat > /etc/default/sdwan-app << EOF
AUTH_METHOD=jwt
JWT_SECRET_KEY=lima-sd-wan-demo-secret-key-at-least-32-chars
JWT_TEST_USERS={"demo":"${DEMO_HASH}"}
CORS_ORIGINS=http://10.10.1.4,http://localhost:58081
EOF

systemctl daemon-reload
systemctl enable --now sdwan-app

echo "=== Cloud2 (on-prem) provisioning complete ==="
