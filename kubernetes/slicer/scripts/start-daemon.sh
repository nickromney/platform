#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: start-daemon.sh [--dry-run] [--execute]

Waits for the configured Slicer endpoint or on-device slicer-mac socket to be
ready for use.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would wait for the configured Slicer daemon endpoint to become ready" "$@"

: "${RUN_DIR:?RUN_DIR is required}"

mkdir -p "$RUN_DIR"
system_dir="${SLICER_SYSTEM_DIR:-${HOME}/slicer-mac}"
system_bin="${SLICER_SYSTEM_BIN:-${system_dir}/slicer-mac}"
system_socket="${SLICER_SYSTEM_SOCKET:-${HOME}/slicer-mac/slicer.sock}"
configured_url="${SLICER_URL:-${SLICER_SOCKET:-}}"
system_wait_seconds="${SLICER_SYSTEM_SOCKET_WAIT_SECONDS:-240}"

socket_ready() {
  local socket="$1"
  local output=""

  output="$(SLICER_URL="$socket" slicer vm list 2>&1)" && return 0
  if printf '%s' "$output" | grep -Eiq 'service not ready|503 Service Unavailable|preparing VM artifacts|launching guest'; then
    return 2
  fi
  return 1
}

start_local_system_daemon() {
  local pid_file="${RUN_DIR}/slicer-mac.pid"
  local log_file="${RUN_DIR}/slicer-mac.log"

  if [ ! -x "${system_bin}" ]; then
    echo "Missing slicer-mac socket: ${system_socket}" >&2
    echo "Cannot auto-start the on-device daemon because ${system_bin} is not executable." >&2
    exit 1
  fi

  echo "Starting on-device slicer-mac from ${system_dir}"
  (
    cd "${system_dir}"
    nohup "${system_bin}" up >"${log_file}" 2>&1 </dev/null &
    echo "$!" >"${pid_file}"
  )
}

if [ -n "$configured_url" ] && [ "$configured_url" != "$system_socket" ]; then
  for _ in $(seq 1 "$system_wait_seconds"); do
    if socket_ready "$configured_url"; then
      echo "Using configured Slicer endpoint ${configured_url}"
      exit 0
    fi
    rc=$?
    if [ "$rc" = "2" ]; then
      sleep 1
      continue
    fi
    sleep 1
  done

  echo "Configured Slicer endpoint ${configured_url} was not ready after ${system_wait_seconds}s" >&2
  echo "Verify SLICER_URL/SLICER_SOCKET (and SLICER_TOKEN_FILE/SLICER_TOKEN if needed), or use kubernetes/kind on Docker-only hosts." >&2
  exit 1
fi

if [ ! -S "$system_socket" ]; then
  start_local_system_daemon
fi

for _ in $(seq 1 "$system_wait_seconds"); do
  if socket_ready "$system_socket"; then
    echo "Using on-device slicer-mac at ${system_socket}"
    exit 0
  fi
  rc=$?
  if [ "$rc" = "2" ]; then
    sleep 1
    continue
  fi
  sleep 1
done

echo "slicer-mac at ${system_socket} was not ready after ${system_wait_seconds}s" >&2
echo "Restart the daemon from ~/slicer-mac and retry." >&2
exit 1
