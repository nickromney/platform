#!/usr/bin/env bash
set -euo pipefail

socket="${SLICER_URL:-${SLICER_SOCKET:-}}"
vm_name="${SLICER_VM_NAME:-slicer-1}"
delete_timeout="${SLICER_RESET_DELETE_TIMEOUT_SECONDS:-20}"

warn() { echo "WARN $*" >&2; }
ok() { echo "OK   $*"; }

[ -n "${socket}" ] || { warn "SLICER_URL or SLICER_SOCKET must be set"; exit 1; }
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
    wait "${delete_pid}"
    rc=$?
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
if [[ "${socket}" == "${HOME}/slicer-mac/slicer.sock" ]]; then
  warn "This looks like the on-device slicer-mac VM. Recycle the daemon/images instead:"
  warn "  ~/slicer-mac/slicer-mac service stop daemon"
  warn "  move ~/slicer-mac/*.img out of the way"
  warn "  ~/slicer-mac/slicer-mac service start daemon"
fi
exit 1
