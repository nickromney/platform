#!/bin/sh
set -eu

REAL_KUBECTL="${KIND_REAL_KUBECTL:-/usr/bin/kubectl}"
MAX_ATTEMPTS="${KIND_KUBECTL_RETRY_ATTEMPTS:-30}"
RETRY_DELAY_SECONDS="${KIND_KUBECTL_RETRY_DELAY_SECONDS:-2}"

stdin_file=""
stdout_file=""
stderr_file=""
WRAPPER_DRY_RUN=0

script_name() {
  basename "$0"
}

print_standard_options() {
  cat <<'EOF'
Options:
  --dry-run  Show a summary and exit before side effects
  --execute  Execute the script body; without it the wrapper prints help and preview output
  -h, --help Show this message
EOF
}

usage() {
  cat <<EOF
Usage: $(script_name) [--dry-run] [--execute] [--] [kubectl args...]

Retry kubectl calls during kind API startup races.

Environment variables:
  KIND_REAL_KUBECTL
  KIND_KUBECTL_RETRY_ATTEMPTS
  KIND_KUBECTL_RETRY_DELAY_SECONDS

$(print_standard_options)
EOF
}

cleanup() {
  [ -n "${stdin_file}" ] && [ -f "${stdin_file}" ] && rm -f "${stdin_file}"
  [ -n "${stdout_file}" ] && [ -f "${stdout_file}" ] && rm -f "${stdout_file}"
  [ -n "${stderr_file}" ] && [ -f "${stderr_file}" ] && rm -f "${stderr_file}"
  return 0
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

# This wrapper is mounted into kind nodes as /usr/local/bin/kubectl, so it must
# remain self-contained and avoid depending on repo-relative helper paths.
WRAPPER_EXECUTE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      WRAPPER_DRY_RUN=1
      shift
      continue
      ;;
    --execute)
      WRAPPER_EXECUTE=1
      shift
      continue
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ "${WRAPPER_DRY_RUN}" = "1" ]; then
  printf 'INFO dry-run: would run kubectl through the kind startup retry wrapper\n'
  exit 0
fi

if [ "${WRAPPER_EXECUTE}" != "1" ]; then
  usage
  printf 'INFO dry-run: would run kubectl through the kind startup retry wrapper\n'
  exit 0
fi

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
