#!/usr/bin/env bash
set -euo pipefail

: "${LIMA_INSTANCE_PREFIX:?LIMA_INSTANCE_PREFIX is required}"
: "${DESIRED_NODES:?DESIRED_NODES is required}"
: "${LIMA_CONFIG:?LIMA_CONFIG is required}"

if ! command -v limactl >/dev/null 2>&1; then
  echo "limactl not found. Install Lima: brew install lima"
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
