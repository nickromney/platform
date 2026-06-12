#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${script_dir}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/scripts/ssh-tunnel-lib.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Ensures host-side SSH tunnels for Lima k3s shared NodePort surfaces.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would ensure Lima shared port tunnels" "$@"

lima_instance="${LIMA_SHARED_PORT_TUNNEL_INSTANCE:-${LIMA_INSTANCE_PREFIX:-k3s-node}-1}"
ports="${LIMA_SHARED_PORT_TUNNEL_PORTS:-30070 30080 30090 31235 30022 30302 30443}"
host="${LIMA_SHARED_PORT_TUNNEL_HOST:-127.0.0.1}"
state_dir="${LIMA_SHARED_PORT_TUNNEL_STATE_DIR:-${REPO_ROOT}/.run/lima}"
pid_file="${state_dir}/shared-port-tunnels-${lima_instance}.pid"
ssh_config="${HOME}/.lima/${lima_instance}/ssh.config"
ssh_host="lima-${lima_instance}"

port_ready() {
  local port="$1"
  nc -z -w 2 "${host}" "${port}" >/dev/null 2>&1
}

all_ports_ready() {
  local port
  for port in ${ports}; do
    port_ready "${port}" || return 1
  done
}

if all_ports_ready; then
  echo "OK   Lima shared port tunnels: ${ports}"
  exit 0
fi

ssh_tunnel_clear_pid_file "${pid_file}"
ssh_tunnel_require_config "${ssh_config}" "${lima_instance}"

mkdir -p "${state_dir}"
forward_args=()
for port in ${ports}; do
  forward_args+=(-L "${host}:${port}:127.0.0.1:${port}")
done

ssh_tunnel_start \
  "${pid_file}" \
  "${ssh_config}" \
  "${ssh_host}" \
  "${forward_args[@]}"

ssh_tunnel_wait_until_ready \
  "${pid_file}" \
  all_ports_ready \
  "OK   Lima shared port tunnels: ${ports}" \
  "Lima shared port tunnel exited before becoming ready." \
  "Timed out waiting for Lima shared port tunnels: ${ports}"
