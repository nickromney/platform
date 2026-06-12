#!/usr/bin/env bash

ssh_tunnel_clear_pid_file() {
  local pid_file="$1"
  local pid=""

  if [[ ! -f "${pid_file}" ]]; then
    return 0
  fi

  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pid_file}"
}

ssh_tunnel_require_config() {
  local ssh_config="$1"
  local instance="$2"

  [[ -f "${ssh_config}" ]] || {
    echo "Lima SSH config not found at ${ssh_config}; start ${instance} first." >&2
    exit 1
  }
}

ssh_tunnel_start() {
  local pid_file="$1"
  local ssh_config="$2"
  local ssh_host="$3"
  shift 3
  local pid=""

  ssh -F "${ssh_config}" \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=2 \
    -N \
    "$@" \
    "${ssh_host}" &
  pid=$!
  printf '%s\n' "${pid}" >"${pid_file}"
}

ssh_tunnel_wait_until_ready() {
  local pid_file="$1"
  local ready_fn="$2"
  local ok_message="$3"
  local exited_message="$4"
  local timeout_message="$5"
  local attempts="${6:-30}"
  local pid=""

  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  for _ in $(seq 1 "${attempts}"); do
    if "${ready_fn}"; then
      echo "${ok_message}"
      return 0
    fi
    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" >/dev/null 2>&1; then
      rm -f "${pid_file}"
      echo "${exited_message}" >&2
      exit 1
    fi
    sleep 1
  done

  kill "${pid}" >/dev/null 2>&1 || true
  rm -f "${pid_file}"
  echo "${timeout_message}" >&2
  exit 1
}
