#!/usr/bin/env bash
set -euo pipefail

# Discover tracked Bats files for make test-ci, minus the reviewable backlog.
# A new *.bats file is gated the moment it is tracked unless it is named in
# tests/ci-gate-backlog.txt.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKLOG_FILE="${CI_GATE_BACKLOG_FILE:-${REPO_ROOT}/tests/ci-gate-backlog.txt}"

git -C "${REPO_ROOT}" ls-files '*.bats' | LC_ALL=C sort | while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  if [[ -f "${BACKLOG_FILE}" ]] && grep -qxF "${file}" "${BACKLOG_FILE}"; then
    continue
  fi
  printf '%s\n' "${file}"
done
