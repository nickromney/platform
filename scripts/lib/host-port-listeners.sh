#!/usr/bin/env bash
# shellcheck shell=bash

host_port_have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

host_port_listeners_for_port_lsof() {
  local bind_ip="$1"
  local port="$2"
  local raw
  local header
  local body

  raw="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  [[ -n "${raw}" ]] || return 1

  if [[ "${bind_ip}" == "0.0.0.0" ]]; then
    printf '%s\n' "${raw}"
    return 0
  fi

  header="$(printf '%s\n' "${raw}" | sed -n '1p')"
  body="$(
    printf '%s\n' "${raw}" | tail -n +2 | \
      grep -E "(^|[[:space:]])(\\*:${port}|127\\.0\\.0\\.1:${port}|localhost:${port}|\\[::1\\]:${port}|::1:${port})([[:space:]]|$)" || true
  )"
  [[ -n "${body}" ]] || return 1
  printf '%s\n%s\n' "${header}" "${body}"
}

host_port_listeners_for_port_ss() {
  local bind_ip="$1"
  local port="$2"
  local body

  body="$(ss -H -ltn "sport = :${port}" 2>/dev/null || true)"
  [[ -n "${body}" ]] || return 1

  if [[ "${bind_ip}" == "127.0.0.1" ]]; then
    body="$(
      printf '%s\n' "${body}" | awk -v port="${port}" '
        {
          addr = $4
          if (addr == "*:" port || addr == "127.0.0.1:" port || addr == "[::1]:" port || addr == "::1:" port) {
            print
          }
        }
      '
    )"
    [[ -n "${body}" ]] || return 1
  fi

  printf 'State Recv-Q Send-Q Local Address:Port Peer Address:Port\n%s\n' "${body}"
}

host_port_listeners_for_port() {
  local bind_ip="$1"
  local port="$2"

  if host_port_have_cmd lsof; then
    host_port_listeners_for_port_lsof "${bind_ip}" "${port}"
    return $?
  fi

  if host_port_have_cmd ss; then
    host_port_listeners_for_port_ss "${bind_ip}" "${port}"
    return $?
  fi

  echo "neither lsof nor ss found in PATH; cannot verify host port availability" >&2
  return 127
}

host_port_listener_addresses_from_lsof() {
  local input="${1-}"

  [[ -n "${input}" ]] || return 0
  printf '%s\n' "${input}" | awk '
    NR == 1 { next }
    {
      addr = ($NF == "(LISTEN)" && NF > 1) ? $(NF - 1) : $NF
      if (addr ~ /^\*:/) {
        sub(/^\*:/, "0.0.0.0:", addr)
      } else if (addr ~ /^localhost:/) {
        sub(/^localhost:/, "127.0.0.1:", addr)
      }
      if (addr ~ /:[0-9]+$/ || addr ~ /^\[[^]]+\]:[0-9]+$/) {
        print addr
      }
    }
  '
}

host_port_listener_addresses_from_ss() {
  local input="${1-}"

  [[ -n "${input}" ]] || return 0
  printf '%s\n' "${input}" | awk '
    {
      addr = ($4 != "" ? $4 : $5)
      if (addr ~ /^\*:/) {
        sub(/^\*:/, "0.0.0.0:", addr)
      } else if (addr ~ /^localhost:/) {
        sub(/^localhost:/, "127.0.0.1:", addr)
      }
      if (addr ~ /:[0-9]+$/ || addr ~ /^\[[^]]+\]:[0-9]+$/) {
        print addr
      }
    }
  '
}

host_port_listener_addresses_for_port() {
  local port="$1"
  local raw_output=""

  if host_port_have_cmd lsof; then
    raw_output="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
    host_port_listener_addresses_from_lsof "${raw_output}"
    return 0
  fi

  if host_port_have_cmd ss; then
    raw_output="$(ss -H -ltn "sport = :${port}" 2>/dev/null || true)"
    host_port_listener_addresses_from_ss "${raw_output}"
    return 0
  fi

  echo "neither lsof nor ss found in PATH; cannot verify host port availability" >&2
  return 127
}

host_port_listener_addresses_for_ports() {
  local ports_text="${1-}"
  local port
  local addresses

  [[ -n "${ports_text}" ]] || return 0

  for port in ${ports_text}; do
    addresses="$(host_port_listener_addresses_for_port "${port}")" || return $?
    printf '%s\n' "${addresses}"
  done | awk 'NF && !seen[$0]++ { print }' | LC_ALL=C sort
}

host_port_binds_overlap() {
  local left_ip="$1"
  local left_port="$2"
  local right_ip="$3"
  local right_port="$4"

  [[ "${left_port}" == "${right_port}" ]] || return 1
  [[ "${left_ip}" == "${right_ip}" || "${left_ip}" == "0.0.0.0" || "${right_ip}" == "0.0.0.0" ]]
}
