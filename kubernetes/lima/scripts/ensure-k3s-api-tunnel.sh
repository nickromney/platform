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

Ensures a host-side SSH tunnel for the Lima k3s API server.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would ensure Lima k3s API tunnel" "$@"

lima_instance="${LIMA_K3S_API_TUNNEL_INSTANCE:-${LIMA_INSTANCE_PREFIX:-k3s-node}-1}"
host_port="${LIMA_K3S_API_TUNNEL_PORT:-16443}"
host="${LIMA_K3S_API_TUNNEL_HOST:-127.0.0.1}"
guest_host="${LIMA_K3S_API_TUNNEL_GUEST_HOST:-127.0.0.1}"
guest_port="${LIMA_K3S_API_TUNNEL_GUEST_PORT:-6443}"
state_dir="${LIMA_K3S_API_TUNNEL_STATE_DIR:-${REPO_ROOT}/.run/lima}"
pid_file="${state_dir}/k3s-api-tunnel-${lima_instance}-${host_port}.pid"
ssh_config="${HOME}/.lima/${lima_instance}/ssh.config"
ssh_host="lima-${lima_instance}"

ready() {
  curl -sk --connect-timeout 2 --max-time 5 "https://${host}:${host_port}/readyz" >/dev/null 2>&1
}

if ready; then
  echo "OK   Lima k3s API tunnel: https://${host}:${host_port}"
  exit 0
fi

ssh_tunnel_clear_pid_file "${pid_file}"
ssh_tunnel_require_config "${ssh_config}" "${lima_instance}"

mkdir -p "${state_dir}"
ssh_tunnel_start \
  "${pid_file}" \
  "${ssh_config}" \
  "${ssh_host}" \
  -L "${host}:${host_port}:${guest_host}:${guest_port}"

ssh_tunnel_wait_until_ready \
  "${pid_file}" \
  ready \
  "OK   Lima k3s API tunnel: https://${host}:${host_port}" \
  "Lima k3s API tunnel exited before becoming ready." \
  "Timed out waiting for Lima k3s API tunnel on ${host}:${host_port}."
