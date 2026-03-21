#!/bin/sh
set -eu

REAL_KUBECTL="${KIND_REAL_KUBECTL:-/usr/bin/kubectl}"
MAX_ATTEMPTS="${KIND_KUBECTL_RETRY_ATTEMPTS:-30}"
RETRY_DELAY_SECONDS="${KIND_KUBECTL_RETRY_DELAY_SECONDS:-2}"

stdin_file=""
stdout_file=""
stderr_file=""

cleanup() {
  [ -n "${stdin_file}" ] && [ -f "${stdin_file}" ] && rm -f "${stdin_file}"
  [ -n "${stdout_file}" ] && [ -f "${stdout_file}" ] && rm -f "${stdout_file}"
  [ -n "${stderr_file}" ] && [ -f "${stderr_file}" ] && rm -f "${stderr_file}"
}

is_retryable_error() {
  grep -Eiq \
    'failed to download openapi|connect: connection refused|the connection to the server .* was refused|i/o timeout|context deadline exceeded|EOF' \
    "${stderr_file}"
}

run_kubectl() {
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  if [ -n "${stdin_file}" ]; then
    "${REAL_KUBECTL}" "$@" <"${stdin_file}" >"${stdout_file}" 2>"${stderr_file}"
  else
    "${REAL_KUBECTL}" "$@" >"${stdout_file}" 2>"${stderr_file}"
  fi
}

trap cleanup EXIT INT TERM

if [ ! -x "${REAL_KUBECTL}" ]; then
  echo "kind node kubectl wrapper: real kubectl not found at ${REAL_KUBECTL}" >&2
  exit 127
fi

if [ ! -t 0 ]; then
  stdin_file="$(mktemp)"
  cat >"${stdin_file}"
fi

attempt=1
while :; do
  if run_kubectl "$@"; then
    cat "${stdout_file}"
    cat "${stderr_file}" >&2
    exit 0
  fi
  status=$?

  if [ "${attempt}" -ge "${MAX_ATTEMPTS}" ] || ! is_retryable_error; then
    cat "${stdout_file}"
    cat "${stderr_file}" >&2
    exit "${status}"
  fi

  echo "kind node kubectl wrapper: transient API startup failure on attempt ${attempt}/${MAX_ATTEMPTS}; retrying in ${RETRY_DELAY_SECONDS}s" >&2
  attempt=$((attempt + 1))
  sleep "${RETRY_DELAY_SECONDS}"
done
