#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/shell-cli.sh"

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
state_dir="${LIMA_SHARED_PORT_TUNNEL_STATE_DIR:-${repo_root}/.run/lima}"
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

if [[ -f "${pid_file}" ]]; then
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pid_file}"
fi

[[ -f "${ssh_config}" ]] || {
  echo "Lima SSH config not found at ${ssh_config}; start ${lima_instance} first." >&2
  exit 1
}

mkdir -p "${state_dir}"
forward_args=()
for port in ${ports}; do
  forward_args+=(-L "${host}:${port}:127.0.0.1:${port}")
done

ssh -F "${ssh_config}" \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=2 \
  -N \
  "${forward_args[@]}" \
  "${ssh_host}" &
pid=$!
printf '%s\n' "${pid}" >"${pid_file}"

for _ in $(seq 1 30); do
  if all_ports_ready; then
    echo "OK   Lima shared port tunnels: ${ports}"
    exit 0
  fi
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    rm -f "${pid_file}"
    echo "Lima shared port tunnel exited before becoming ready." >&2
    exit 1
  fi
  sleep 1
done

kill "${pid}" >/dev/null 2>&1 || true
rm -f "${pid_file}"
echo "Timed out waiting for Lima shared port tunnels: ${ports}" >&2
exit 1
