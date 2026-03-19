#!/usr/bin/env bash
set -euo pipefail

socket="${SLICER_URL:-${SLICER_SOCKET:-}}"
vm_name="${SLICER_VM_NAME:-slicer-1}"
delete_timeout="${SLICER_RESET_DELETE_TIMEOUT_SECONDS:-20}"
system_socket="${SLICER_SYSTEM_SOCKET:-${HOME}/slicer-mac/slicer.sock}"
system_dir="${SLICER_SYSTEM_DIR:-${HOME}/slicer-mac}"
system_bin="${SLICER_SYSTEM_BIN:-${system_dir}/slicer-mac}"
recycle_wait_seconds="${SLICER_SYSTEM_SOCKET_WAIT_SECONDS:-60}"
pause_wait_seconds="${SLICER_RESET_PAUSE_TIMEOUT_SECONDS:-30}"

warn() { echo "WARN $*" >&2; }
ok() { echo "OK   $*"; }

[ -n "${socket}" ] || { warn "SLICER_URL or SLICER_SOCKET must be set"; exit 1; }
command -v slicer >/dev/null 2>&1 || { warn "slicer not found in PATH"; exit 1; }
command -v jq >/dev/null 2>&1 || { warn "jq not found in PATH"; exit 1; }

manual_recycle_hint() {
  warn "This looks like the on-device slicer-mac VM. Recycle the daemon/images instead:"
  warn "  ~/slicer-mac/slicer-mac service stop daemon"
  warn "  move ~/slicer-mac/*.img out of the way"
  warn "  ~/slicer-mac/slicer-mac service start daemon"
}

wait_for_system_socket_ready() {
  for _ in $(seq 1 "${recycle_wait_seconds}"); do
    if SLICER_URL="${socket}" slicer vm list --json >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

pause_system_vm() {
  local status=""

  if ! SLICER_URL="${socket}" slicer vm list --json | jq -e --arg vm "${vm_name}" '.[] | select(.hostname == $vm)' >/dev/null 2>&1; then
    return 0
  fi

  SLICER_URL="${socket}" slicer vm pause "${vm_name}" >/dev/null 2>&1 || true

  for _ in $(seq 1 "${pause_wait_seconds}"); do
    status="$(
      SLICER_URL="${socket}" slicer vm list --json 2>/dev/null | \
        jq -r --arg vm "${vm_name}" '.[] | select(.hostname == $vm) | .status // empty' || true
    )"
    if [[ -z "${status}" || "${status}" == "Paused" || "${status}" == "Stopped" ]]; then
      ok "left ${vm_name} ${status:-absent} after recycle"
      return 0
    fi
    sleep 1
  done

  warn "recreated ${vm_name} is still ${status:-Running} after pause request"
  return 1
}

recycle_system_vm() {
  local recycle_stamp recycle_dir recycled_any=0

  if [[ "${socket}" != "${system_socket}" ]]; then
    return 1
  fi

  if [[ ! -x "${system_bin}" ]]; then
    warn "cannot recycle on-device slicer-mac automatically; missing ${system_bin}"
    return 1
  fi

  recycle_stamp="$(date -u +%Y%m%d%H%M%S)"
  recycle_dir="${system_dir}/recycled-${recycle_stamp}"
  mkdir -p "${recycle_dir}"

  echo "INFO recycling on-device slicer-mac state for ${vm_name}"
  "${system_bin}" service stop daemon >/dev/null 2>&1 || warn "failed to stop on-device slicer-mac daemon cleanly"

  for artifact in \
    "${system_dir}/${vm_name}.img" \
    "${system_dir}/${vm_name}.log" \
    "${system_dir}/${vm_name}-vsock.sock"; do
    if [[ -e "${artifact}" || -L "${artifact}" ]]; then
      mv "${artifact}" "${recycle_dir}/"
      recycled_any=1
    fi
  done

  if [[ "${recycled_any}" -eq 0 ]]; then
    warn "no recyclable on-device artifacts were found for ${vm_name}; restarting slicer-mac anyway"
  fi

  "${system_bin}" service start daemon >/dev/null 2>&1 || {
    warn "failed to restart on-device slicer-mac daemon"
    return 1
  }

  if ! wait_for_system_socket_ready; then
    warn "on-device slicer-mac did not become ready after ${recycle_wait_seconds}s"
    return 1
  fi

  if ! pause_system_vm; then
    return 1
  fi

  ok "recycled on-device slicer-mac state for ${vm_name}"
  ok "archived prior VM artifacts under ${recycle_dir}"
  return 0
}

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
cleanup() {
  rm -f "${delete_log}"
}
trap cleanup EXIT

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
    if recycle_system_vm; then
      exit 0
    fi
    if [[ "${socket}" == "${system_socket}" ]]; then
      manual_recycle_hint
    fi
    exit 1
  fi
  sleep 1
done

kill "${delete_pid}" >/dev/null 2>&1 || true
wait "${delete_pid}" 2>/dev/null || true

warn "delete of ${vm_name} did not complete within ${delete_timeout}s"
if recycle_system_vm; then
  exit 0
fi
if [[ "${socket}" == "${system_socket}" ]]; then
  manual_recycle_hint
fi
exit 1
