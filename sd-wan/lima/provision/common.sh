#!/bin/bash
# Common provisioning for all Lima VMs
# Installs shared packages and sets up base networking
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--execute]

Run the shared guest provisioning steps for every SD-WAN Lima VM.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run shared SD-WAN Lima guest provisioning steps" "$@"

if [ "${TRACE_PROVISIONING:-0}" = "1" ]; then
    set -x
fi

export DEBIAN_FRONTEND=noninteractive

echo "=== Common provisioning for $CLOUD_NAME ($CLOUD_ROLE) ==="

# Keep sudo quiet by ensuring the active guest hostname resolves locally.
bash "$PROJECT_DIR/provision/fix-hostname.sh" "$CLOUD_NAME"

# Install required packages
apt-get update
apt-get install -y --no-install-recommends \
    wireguard-tools \
    nginx \
    iptables \
    iproute2 \
    dnsutils \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    jq \
    net-tools \
    tcpdump \
    traceroute \
    openssl

# Install CoreDNS
COREDNS_VERSION="1.11.1"
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "arm64" ]; then
    COREDNS_ARCH="arm64"
else
    COREDNS_ARCH="amd64"
fi
curl -fsSL "https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_${COREDNS_ARCH}.tgz" \
    | tar xz -C /usr/local/bin/
chmod +x /usr/local/bin/coredns

# Install step CLI for PKI
if [ "$ARCH" = "arm64" ]; then
    STEP_ARCH="arm64"
else
    STEP_ARCH="amd64"
fi
STEP_VERSION=$(curl -fsSL "https://api.github.com/repos/smallstep/cli/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
curl -fsSL "https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/step_linux_${STEP_VERSION}_${STEP_ARCH}.tar.gz" -o /tmp/step.tgz
tar xzf /tmp/step.tgz -C /tmp
install -m 0755 "/tmp/step_${STEP_VERSION}/bin/step" /usr/local/bin/step
rm -rf /tmp/step.tgz "/tmp/step_${STEP_VERSION}"

# Install FastAPI app dependencies
python3 -m venv /opt/app-venv
/opt/app-venv/bin/pip install fastapi uvicorn httpx pyjwt 'pwdlib[argon2]' pydantic python-multipart

# Create directories
mkdir -p /etc/coredns /etc/wireguard /etc/pki /opt/app

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sdwan.conf

echo "=== Common provisioning complete ==="
