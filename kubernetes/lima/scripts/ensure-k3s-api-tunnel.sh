#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/shell-cli.sh"

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
state_dir="${LIMA_K3S_API_TUNNEL_STATE_DIR:-${repo_root}/.run/lima}"
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
ssh -F "${ssh_config}" \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=2 \
  -N \
  -L "${host}:${host_port}:${guest_host}:${guest_port}" \
  "${ssh_host}" &
pid=$!
printf '%s\n' "${pid}" >"${pid_file}"

for _ in $(seq 1 30); do
  if ready; then
    echo "OK   Lima k3s API tunnel: https://${host}:${host_port}"
    exit 0
  fi
  if ! kill -0 "${pid}" >/dev/null 2>&1; then
    rm -f "${pid_file}"
    echo "Lima k3s API tunnel exited before becoming ready." >&2
    exit 1
  fi
  sleep 1
done

kill "${pid}" >/dev/null 2>&1 || true
rm -f "${pid_file}"
echo "Timed out waiting for Lima k3s API tunnel on ${host}:${host_port}." >&2
exit 1
