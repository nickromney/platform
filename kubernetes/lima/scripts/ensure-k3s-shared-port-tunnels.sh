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
# An entry is either a port, tunnelled to the same port in the VM, or
# host:vm when the two differ. The gateway needs the second form: Cilium's
# Envoy runs host-networked in the VM and binds 443 there, while the host's
# own 443 already belongs to the proxy container that fronts this tunnel.
ports="${LIMA_SHARED_PORT_TUNNEL_PORTS:-30070:443 30080 30090 31235 30022 30302 30443}"
host="${LIMA_SHARED_PORT_TUNNEL_HOST:-127.0.0.1}"
state_dir="${LIMA_SHARED_PORT_TUNNEL_STATE_DIR:-${REPO_ROOT}/.run/lima}"
pid_file="${state_dir}/shared-port-tunnels-${lima_instance}.pid"
ssh_config="${HOME}/.lima/${lima_instance}/ssh.config"
ssh_host="lima-${lima_instance}"

host_port_of() {
  printf '%s\n' "${1%%:*}"
}

vm_port_of() {
  printf '%s\n' "${1##*:}"
}

port_ready() {
  local port="$1"
  nc -z -w 2 "${host}" "${port}" >/dev/null 2>&1
}

all_ports_ready() {
  local entry
  for entry in ${ports}; do
    port_ready "$(host_port_of "${entry}")" || return 1
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
for entry in ${ports}; do
  forward_args+=(-L "${host}:$(host_port_of "${entry}"):127.0.0.1:$(vm_port_of "${entry}")")
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
