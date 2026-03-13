#!/usr/bin/env bash
set -euo pipefail

: "${RUN_DIR:?RUN_DIR is required}"

pid_file="$RUN_DIR/slicer-mac.pid"
active_file="$RUN_DIR/slicer.sock.active"

shutdown_managed_vms() {
  local socket="$1"
  local vms=""

  command -v slicer >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  vms="$(SLICER_URL="$socket" slicer vm list --json 2>/dev/null | jq -r '.[] | select(.status == "Running") | .hostname' || true)"
  [ -n "$vms" ] || return 0

  while IFS= read -r vm; do
    [ -n "$vm" ] || continue
    echo "Requesting clean shutdown for $vm"
    SLICER_URL="$socket" slicer vm shutdown "$vm" >/dev/null 2>&1 || true
  done <<<"$vms"

  for _ in $(seq 1 20); do
    remaining="$(SLICER_URL="$socket" slicer vm list --json 2>/dev/null | jq -r '.[] | select(.status == "Running") | .hostname' || true)"
    [ -z "$remaining" ] && return 0
    sleep 1
  done
}

if [ ! -f "$pid_file" ]; then
  echo "slicer-mac is not running (no pid file)"
  exit 0
fi

pid="$(cat "$pid_file")"
if [ -z "$pid" ]; then
  rm -f "$pid_file"
  exit 0
fi

if ! ps -p "$pid" >/dev/null 2>&1; then
  rm -f "$pid_file"
  echo "slicer-mac already stopped"
  exit 0
fi

if [ -f "$active_file" ]; then
  active_socket="$(cat "$active_file" 2>/dev/null || true)"
  if [ -n "$active_socket" ]; then
    shutdown_managed_vms "$active_socket"
  fi
fi

kill "$pid" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  if ! ps -p "$pid" >/dev/null 2>&1; then
    rm -f "$pid_file"
    echo "Stopped slicer-mac (pid=$pid)"
    exit 0
  fi
  sleep 1
done

echo "slicer-mac did not stop gracefully, forcing kill"
kill -9 "$pid" >/dev/null 2>&1 || true
rm -f "$pid_file"
