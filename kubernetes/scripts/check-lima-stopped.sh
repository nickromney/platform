#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/shell-cli.sh"

lima_instance_prefix="${LIMA_INSTANCE_PREFIX:-k3s-node}"
LIMA_SHARED_PORT_NUMBERS="443 30022 30080 30090 31235 3301 3302"
running_lima_vms=""
running_lima_proxies=""
active_shared_ports=""

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Checks whether Lima VMs or host proxy containers are still running and exits
non-zero when they would conflict with another local runtime.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would check whether Lima VMs or proxies are still running" "$@"

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

  for port in ${LIMA_SHARED_PORT_NUMBERS}; do
    if shared_port_listening "${port}"; then
      ports+="${port}"$'\n'
    fi
  done

  if [[ -n "${ports}" ]]; then
    printf '%s' "${ports}" | LC_ALL=C sort -n -u
  fi
}

if command -v limactl >/dev/null 2>&1; then
  running_lima_vms="$(
    limactl list 2>/dev/null | \
      awk -v prefix="^${lima_instance_prefix}-[0-9]+$" '$1 ~ prefix && $2 == "Running" { print $1 }' || true
  )"
fi

if command -v docker >/dev/null 2>&1; then
  running_lima_proxies="$(
    docker ps --format '{{.Names}}' 2>/dev/null | \
      grep -E '^(limavm-platform-gateway-443)$' || true
  )"
fi

if [[ -z "${running_lima_vms}" && -z "${running_lima_proxies}" ]]; then
  exit 0
fi

active_shared_ports="$(shared_ports_in_use)"

echo "Lima is still running." >&2
echo "Stop it before assuming the shared localhost ports are free:" >&2
echo "  make -C kubernetes/lima stop-lima" >&2
echo "" >&2

if [[ -n "${active_shared_ports}" ]]; then
  echo "Conflicting shared host ports currently in use by Lima:" >&2
  while IFS= read -r port; do
    [[ -z "${port}" ]] && continue
    printf '  127.0.0.1:%s\n' "${port}" >&2
  done <<< "${active_shared_ports}"
  echo "" >&2
fi

if [[ -n "${running_lima_vms}" ]]; then
  echo "Running Lima VMs:" >&2
  while IFS= read -r vm; do
    [[ -z "${vm}" ]] && continue
    printf '  %s\n' "${vm}" >&2
  done <<< "${running_lima_vms}"
fi

if [[ -n "${running_lima_proxies}" ]]; then
  [[ -n "${running_lima_vms}" ]] && echo "" >&2
  echo "Running Lima proxy containers:" >&2
  while IFS= read -r container; do
    [[ -z "${container}" ]] && continue
    printf '  %s\n' "${container}" >&2
  done <<< "${running_lima_proxies}"
fi

exit 1
