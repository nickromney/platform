#!/usr/bin/env bash
set -euo pipefail

# Discover tracked Bats files for make test-ci, minus the reviewable backlog.
# A new *.bats file is gated the moment it is tracked unless it is named in
# tests/ci-gate-backlog.txt.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
BACKLOG_FILE="${CI_GATE_BACKLOG_FILE:-${REPO_ROOT}/tests/ci-gate-backlog.txt}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

List tracked Bats files for make test-ci, minus tests/ci-gate-backlog.txt.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would list tracked Bats files minus ${BACKLOG_FILE}" "$@"

git -C "${REPO_ROOT}" ls-files '*.bats' | LC_ALL=C sort | while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  if [[ -f "${BACKLOG_FILE}" ]] && grep -qxF "${file}" "${BACKLOG_FILE}"; then
    continue
  fi
  printf '%s\n' "${file}"
done
