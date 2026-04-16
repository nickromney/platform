#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/shell-cli.sh"

slicer_socket="${SLICER_SOCKET:-${SLICER_URL:-${SLICER_SYSTEM_SOCKET:-${HOME}/slicer-mac/slicer.sock}}}"
slicer_vm_name="${SLICER_VM_NAME:-slicer-1}"
SLICER_SHARED_PORT_NUMBERS="443 30022 30080 30090 31235 3301 3302"
running_slicer_vm=""
running_slicer_forwards=""
running_slicer_proxies=""
active_shared_ports=""

usage() {
  cat <<EOF
Usage: check-slicer-stopped.sh [--dry-run] [--execute]

Checks whether Slicer VMs, host-forward processes, or proxy containers are
still running and exits non-zero when they would conflict with another runtime.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would check whether Slicer VMs or proxy processes are still running" "$@"

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

shared_port_listening() {
  local port="$1"

  if have_cmd lsof; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if have_cmd ss; then
    ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .
    return
  fi

  return 1
}

shared_ports_in_use() {
  local port
  local ports=""

  for port in ${SLICER_SHARED_PORT_NUMBERS}; do
    if shared_port_listening "${port}"; then
      ports+="${port}"$'\n'
    fi
  done

  if [[ -n "${ports}" ]]; then
    printf '%s' "${ports}" | LC_ALL=C sort -n -u
  fi
}

if command -v slicer >/dev/null 2>&1; then
  if command -v jq >/dev/null 2>&1; then
    running_slicer_vm="$(
      SLICER_URL="${slicer_socket}" slicer vm list --json 2>/dev/null | \
        jq -r --arg vm "${slicer_vm_name}" '.[] | select(.hostname == $vm and .status == "Running") | .hostname' || true
    )"
  else
    running_slicer_vm="$(
      SLICER_URL="${slicer_socket}" slicer vm list 2>/dev/null | \
        awk -v vm="${slicer_vm_name}" '$1 == vm && /Running/ { print $1 }' || true
    )"
  fi
fi

running_slicer_forwards="$(
  ps -ax -o comm=,args= 2>/dev/null | \
    awk 'index($0, "slicer vm forward") && $1 != "awk" && $1 != "bash" && $1 != "sh" { sub(/^[^[:space:]]+[[:space:]]+/, "", $0); print $0 }' || true
)"

if command -v docker >/dev/null 2>&1; then
  running_slicer_proxies="$(
    docker ps --format '{{.Names}}' 2>/dev/null | \
      grep -E '^(slicer-platform-gateway-443)$' || true
  )"
fi

if [[ -z "${running_slicer_vm}" && -z "${running_slicer_forwards}" && -z "${running_slicer_proxies}" ]]; then
  exit 0
fi

active_shared_ports="$(shared_ports_in_use)"

echo "Slicer is still running." >&2
echo "Stop it before assuming the shared localhost ports are free:" >&2
echo "  make -C kubernetes/slicer stop-slicer" >&2
echo "" >&2

if [[ -n "${active_shared_ports}" ]]; then
  echo "Conflicting shared host ports currently in use by Slicer:" >&2
  while IFS= read -r port; do
    [[ -z "${port}" ]] && continue
    printf '  127.0.0.1:%s\n' "${port}" >&2
  done <<< "${active_shared_ports}"
  echo "" >&2
fi

if [[ -n "${running_slicer_vm}" ]]; then
  echo "Running Slicer VM:" >&2
  while IFS= read -r vm; do
    [[ -z "${vm}" ]] && continue
    printf '  %s\n' "${vm}" >&2
  done <<< "${running_slicer_vm}"
fi

if [[ -n "${running_slicer_forwards}" ]]; then
  [[ -n "${running_slicer_vm}" ]] && echo "" >&2
  echo "Running Slicer host forward processes:" >&2
  while IFS= read -r cmd; do
    [[ -z "${cmd}" ]] && continue
    printf '  %s\n' "${cmd}" >&2
  done <<< "${running_slicer_forwards}"
fi

if [[ -n "${running_slicer_proxies}" ]]; then
  if [[ -n "${running_slicer_vm}" || -n "${running_slicer_forwards}" ]]; then
    echo "" >&2
  fi
  echo "Running Slicer proxy containers:" >&2
  while IFS= read -r container; do
    [[ -z "${container}" ]] && continue
    printf '  %s\n' "${container}" >&2
  done <<< "${running_slicer_proxies}"
fi

exit 1
