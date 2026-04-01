#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

socket="${SLICER_URL:-${SLICER_SOCKET:-}}"
vm_name="${SLICER_VM_NAME:-slicer-1}"
delete_timeout="${SLICER_RESET_DELETE_TIMEOUT_SECONDS:-20}"
system_socket="${SLICER_SYSTEM_SOCKET:-${HOME}/slicer-mac/slicer.sock}"
system_dir="${SLICER_SYSTEM_DIR:-${HOME}/slicer-mac}"
system_bin="${SLICER_SYSTEM_BIN:-${system_dir}/slicer-mac}"

warn() { echo "WARN $*" >&2; }
ok() { echo "OK   $*"; }

usage() {
  cat <<EOF
Usage: delete-vm-best-effort.sh [--dry-run] [--execute]

Best-effort cleanup for the managed Slicer VM, including local slicer-mac disk
artifacts when applicable.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would best-effort delete the configured Slicer VM and related local artifacts" "$@"

[ -n "${socket}" ] || { warn "SLICER_URL or SLICER_SOCKET must be set"; exit 1; }

manual_local_cleanup_hint() {
  warn "Manual on-device cleanup:"
  warn "  ${system_bin} service stop daemon"
  warn "  pkill -f 'slicer-mac up'"
  warn "  rm -f ${system_dir}/${vm_name}*.img"
}

local_system_daemon_pids() {
  ps -ax -o pid=,args= 2>/dev/null | awk -v bin="${system_bin}" '
    index($0, bin " up") || $0 ~ /(^|[[:space:]])\.\/slicer-mac up([[:space:]]|$)/ { print $1 }
  ' || true
}

stop_local_system_daemon_processes() {
  local pids pid stopped_any=0

  pids="$(local_system_daemon_pids)"
  [[ -n "${pids}" ]] || return 0

  echo "INFO stopping foreground slicer-mac daemon process(es)"
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] || continue
    stopped_any=1
    kill "${pid}" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
      if ! ps -p "${pid}" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    if ps -p "${pid}" >/dev/null 2>&1; then
      kill -9 "${pid}" >/dev/null 2>&1 || true
    fi
  done <<< "${pids}"

  if [[ "${stopped_any}" -eq 1 ]]; then
    ok "stopped foreground slicer-mac daemon process(es)"
  fi
}

cleanup_local_system_vm() {
  local artifact removed=0
  if [[ ! -x "${system_bin}" ]]; then
    warn "cannot stop on-device slicer-mac automatically; missing ${system_bin}"
    return 1
  fi

  echo "INFO stopping on-device slicer-mac daemon before pruning ${vm_name} disk images"
  if ! "${system_bin}" service stop daemon >/dev/null 2>&1; then
    warn "launchd-managed slicer-mac daemon was not running or did not stop cleanly"
  fi
  stop_local_system_daemon_processes
  ok "stopped on-device slicer-mac daemon"

  shopt -s nullglob
  for artifact in "${system_dir}/${vm_name}"*.img; do
    rm -f "${artifact}"
    removed=$((removed + 1))
  done
  shopt -u nullglob

  if [[ "${removed}" -eq 0 ]]; then
    ok "no on-device disk images matched ${system_dir}/${vm_name}*.img"
  else
    ok "removed ${removed} on-device disk image(s) matching ${system_dir}/${vm_name}*.img"
  fi
}

if [[ "${socket}" == "${system_socket}" ]]; then
  if cleanup_local_system_vm; then
    exit 0
  fi
  manual_local_cleanup_hint
  exit 1
fi

command -v slicer >/dev/null 2>&1 || { warn "slicer not found in PATH"; exit 1; }
command -v jq >/dev/null 2>&1 || { warn "jq not found in PATH"; exit 1; }

if ! SLICER_URL="${socket}" slicer vm list --json | jq -e --arg vm "${vm_name}" '.[] | select(.hostname == $vm)' >/dev/null 2>&1; then
  ok "no VM named ${vm_name}"
  exit 0
fi

echo "INFO shutting down ${vm_name} cleanly before delete"
SLICER_URL="${socket}" slicer vm shutdown "${vm_name}" >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
  status="$(SLICER_URL="${socket}" slicer vm list --json | jq -r --arg vm "${vm_name}" '.[] | select(.hostname == $vm) | .status // empty')"
  if [ -z "${status}" ] || [ "${status}" != "Running" ]; then
    break
  fi
  sleep 1
done

delete_log="$(mktemp)"
trap 'rm -f "${delete_log}"' EXIT

set +e
SLICER_URL="${socket}" slicer vm delete "${vm_name}" >"${delete_log}" 2>&1 &
delete_pid=$!
set -e

for _ in $(seq 1 "${delete_timeout}"); do
  if ! kill -0 "${delete_pid}" >/dev/null 2>&1; then
    set +e
    wait "${delete_pid}"
    rc=$?
    set -e
    if [ "${rc}" -eq 0 ]; then
      ok "deleted ${vm_name}"
      exit 0
    fi
    warn "slicer vm delete ${vm_name} failed"
    sed 's/^/  /' "${delete_log}" >&2 || true
    exit 1
  fi
  sleep 1
done

kill "${delete_pid}" >/dev/null 2>&1 || true
wait "${delete_pid}" 2>/dev/null || true

warn "delete of ${vm_name} did not complete within ${delete_timeout}s"
exit 1
