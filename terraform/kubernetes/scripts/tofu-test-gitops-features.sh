#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "${STACK_DIR}/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

TIMEOUT_SECONDS="${TOFU_GITOPS_FEATURES_TEST_TIMEOUT_SECONDS:-180}"
TEST_FILTER="${TOFU_GITOPS_FEATURES_TEST_FILTER:-tests/gitops_features.tftest.hcl}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Runs the GitOps feature Terraform test with a hard wall-clock bound and prints
diagnostics if OpenTofu or provider processes outlive the timeout.

Environment:
  TOFU_GITOPS_FEATURES_TEST_TIMEOUT_SECONDS  Timeout in seconds (default: 180)
  TOFU_GITOPS_FEATURES_TEST_FILTER           tofu test filter (default: tests/gitops_features.tftest.hcl)

$(shell_cli_standard_options)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  shell_cli_handle_standard_no_args usage "would run bounded tofu test -filter=${TEST_FILTER}" "$@"
fi

list_tofu_processes() {
  pgrep -af 'tofu|terraform-provider|terraform' 2>/dev/null || true
}

kill_process_tree() {
  local pid="$1"

  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -P "${pid}" 2>/dev/null || true
  fi
  kill -TERM "${pid}" 2>/dev/null || true
  sleep 2
  if command -v pkill >/dev/null 2>&1; then
    pkill -KILL -P "${pid}" 2>/dev/null || true
  fi
  kill -KILL "${pid}" 2>/dev/null || true
}

run_bounded_tofu_test() {
  local output_file pid start elapsed rc=0

  command -v tofu >/dev/null 2>&1 || { echo "tofu not found in PATH" >&2; return 127; }
  output_file="$(mktemp)"
  tofu -chdir="${STACK_DIR}" test -filter="${TEST_FILTER}" >"${output_file}" 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "${pid}" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [ "${elapsed}" -ge "${TIMEOUT_SECONDS}" ]; then
      echo "Timed out after ${TIMEOUT_SECONDS}s: tofu test -filter=${TEST_FILTER}" >&2
      echo "OpenTofu/provider processes at timeout:" >&2
      list_tofu_processes >&2
      kill_process_tree "${pid}"
      cat "${output_file}" >&2
      rm -f "${output_file}"
      return 124
    fi
    sleep 2
  done

  if ! wait "${pid}"; then
    rc=$?
  fi
  cat "${output_file}"
  rm -f "${output_file}"
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_bounded_tofu_test
fi
