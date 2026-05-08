#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "${STACK_DIR}/../.." && pwd)}"
RUNNER="${SCRIPT_DIR}/run-opentofu-tests.sh"
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
  local rc=0

  TOFU_TEST_TIMEOUT_SECONDS="${TIMEOUT_SECONDS}" \
    TOFU_TEST_FILTER="${TEST_FILTER}" \
    "${RUNNER}" --execute \
    --module-dir "${STACK_DIR}" \
    --filter "${TEST_FILTER}" \
    --timeout-seconds "${TIMEOUT_SECONDS}" || rc=$?

  if [[ "${rc}" -eq 124 ]]; then
    return 124
  fi
  return "${rc}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_bounded_tofu_test
fi
