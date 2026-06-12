#!/usr/bin/env bash

k3s_bootstrap_find_client() {
  local candidate

  for candidate in \
    "${K3SUP_PRO_BIN:-}" \
    "$(command -v k3sup-pro 2>/dev/null || true)" \
    "${K3SUP_BIN:-}" \
    "$(command -v k3sup 2>/dev/null || true)" \
    "$HOME/.arkade/bin/k3sup"; do
    [ -n "${candidate}" ] || continue
    [ -x "${candidate}" ] || continue
    echo "${candidate}"
    return 0
  done

  return 1
}

k3s_bootstrap_channel_args() {
  local channel="$1"
  local version="$2"

  if [ -n "${version}" ]; then
    printf '%s\n' "--k3s-version ${version}"
  else
    printf '%s\n' "--k3s-channel ${channel}"
  fi
}

k3s_bootstrap_run_with_timeout() {
  local seconds="$1"
  shift
  local pid=""
  local start=""
  local elapsed=""
  local rc=0

  if command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}" "$@"
    return $?
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${seconds}" "$@"
    return $?
  fi

  "$@" &
  pid=$!
  start="$(date +%s)"

  while kill -0 "${pid}" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [ "${elapsed}" -ge "${seconds}" ]; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
  done

  wait "${pid}" || rc=$?
  return "${rc}"
}
