#!/usr/bin/env bash
set -euo pipefail

: "${SLICER_SOCKET:?SLICER_SOCKET is required}"
: "${CONFIG_FILE:?CONFIG_FILE is required}"
: "${SLICER_SBOX_CPUS:=4}"
: "${SLICER_SBOX_RAM_GB:=12}"
: "${SLICER_SBOX_STORAGE_SIZE:=20G}"

mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" <<EOF
config:
  power_events: true
  host_groups:
    - name: sbox
      count: 1
      vcpu: ${SLICER_SBOX_CPUS}
      ram_gb: ${SLICER_SBOX_RAM_GB}
      storage_size: ${SLICER_SBOX_STORAGE_SIZE}
      share_home: ""
      rosetta: false
      sleep_action: prevent
      network:
        mode: nat
        gateway: 192.168.64.1/24

  image: "ghcr.io/openfaasltd/slicer-systemd-2404-arm64-avz:6.12.70-aarch64-avz-latest"
  hypervisor: apple
  api:
    socket: "${SLICER_SOCKET}"
EOF

echo "Wrote ${CONFIG_FILE}"
echo "Socket: ${SLICER_SOCKET}"
