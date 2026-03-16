#!/usr/bin/env bash
set -euo pipefail

: "${RUN_DIR:?RUN_DIR is required}"

pid_file="$RUN_DIR/slicer-mac.pid"

if [ ! -f "$pid_file" ]; then
  echo "No project-managed slicer-mac daemon to stop"
  exit 0
fi

pid="$(cat "$pid_file")"
if [ -z "$pid" ]; then
  rm -f "$pid_file"
  echo "Removed empty stale slicer-mac pid file"
  exit 0
fi

if ! ps -p "$pid" >/dev/null 2>&1; then
  rm -f "$pid_file"
  echo "Removed stale slicer-mac pid file"
  exit 0
fi

echo "Stopping stale project-managed slicer-mac (pid=$pid)"
kill "$pid" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  if ! ps -p "$pid" >/dev/null 2>&1; then
    rm -f "$pid_file"
    echo "Stopped stale project-managed slicer-mac (pid=$pid)"
    exit 0
  fi
  sleep 1
done

echo "slicer-mac did not stop gracefully, forcing kill"
kill -9 "$pid" >/dev/null 2>&1 || true
rm -f "$pid_file"
