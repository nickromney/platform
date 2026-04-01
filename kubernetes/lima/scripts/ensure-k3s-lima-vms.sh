#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ensure-k3s-lima-vms.sh [--dry-run] [--execute]

Ensures the expected set of Lima VMs exist and are running for the Lima k3s
workflow.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would ensure the configured Lima VM set exists and is running" "$@"

: "${LIMA_INSTANCE_PREFIX:?LIMA_INSTANCE_PREFIX is required}"
: "${DESIRED_NODES:?DESIRED_NODES is required}"
: "${LIMA_CONFIG:?LIMA_CONFIG is required}"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"

print_install_hint() {
  local tool="$1"
  if [ -x "${INSTALL_HINTS}" ]; then
    echo "Install hint:" >&2
    "${INSTALL_HINTS}" --execute --plain "${tool}" >&2 || true
  fi
}

if ! command -v limactl >/dev/null 2>&1; then
  echo "limactl not found in PATH" >&2
  print_install_hint "limactl"
  exit 1
fi

if [ ! -f "$LIMA_CONFIG" ]; then
  echo "Lima config not found: $LIMA_CONFIG"
  exit 1
fi

get_status() {
  local name="$1"
  limactl list 2>/dev/null | awk -v n="$name" '$1==n {print $2}' | head -1
}

for i in $(seq 1 "$DESIRED_NODES"); do
  name="${LIMA_INSTANCE_PREFIX}-${i}"
  status="$(get_status "$name")"

  if [ -z "$status" ]; then
    echo "Creating Lima VM: ${name}"
    limactl start --name "$name" "$LIMA_CONFIG" --containerd none --tty=false --timeout=15m
  elif [ "$status" = "Stopped" ]; then
    echo "Starting existing Lima VM: ${name}"
    limactl start "$name" --containerd none --tty=false --timeout=10m
  else
    echo "Lima VM ${name}: ${status}"
  fi
done

echo "Waiting for ${DESIRED_NODES} running Lima VMs..."
for _ in $(seq 1 60); do
  running=0
  for i in $(seq 1 "$DESIRED_NODES"); do
    s="$(get_status "${LIMA_INSTANCE_PREFIX}-${i}")"
    [ "$s" = "Running" ] && running=$((running + 1))
  done
  if [ "$running" -ge "$DESIRED_NODES" ]; then
    echo "All ${DESIRED_NODES} Lima VMs are running"
    limactl list | grep -E "^(NAME|${LIMA_INSTANCE_PREFIX})" || true
    exit 0
  fi
  sleep 5
done

echo "Timed out waiting for Lima VMs to become Running"
limactl list || true
exit 1
