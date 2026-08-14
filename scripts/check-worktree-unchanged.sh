#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

MODE=""
SNAPSHOT_FILE=""

usage() {
  cat <<EOF
Usage: ${0##*/} [--snapshot <file>] [--verify <file>] [--dry-run] [--execute]

Assert that a command left the working tree exactly as it found it.

Take a snapshot before running a test suite, verify after it. Verification
fails if the run introduced, removed, or modified anything that `git status`
can see.

This exists because a test that silently does not do what it claims can still
pass. The regression that motivated it was a stray line continuation that made
`touch` swallow the following `cp` command: the suite stayed green, a fixture
was quietly created empty instead of copied, and the only outward evidence was
an untracked file named `cp` in the repo root that nobody attributed to a test.

A dirty tree at snapshot time is fine and expected mid-session. The assertion
is that the run changed nothing, not that the tree started clean.

Options:
  --snapshot FILE  Record the current \`git status\` to FILE
  --verify FILE    Compare the current \`git status\` against FILE
$(shell_cli_standard_options)
EOF
}

fail() { echo "check-worktree-unchanged: $*" >&2; exit 1; }

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --snapshot)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--snapshot"; exit 1; }
      MODE="snapshot"
      SNAPSHOT_FILE="$2"
      shift 2
      ;;
    --verify)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--verify"; exit 1; }
      MODE="verify"
      SNAPSHOT_FILE="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would ${MODE:-snapshot or verify} the working tree against ${SNAPSHOT_FILE:-a snapshot file}"

[[ -n "${MODE}" ]] || { usage; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail "not inside a git work tree"

# --porcelain is the stable, script-facing format; -unormal reports untracked
# files individually rather than collapsing them into their directory, so a
# single stray file is still named.
capture_status() {
  git status --porcelain -unormal
}

case "${MODE}" in
  snapshot)
    mkdir -p "$(dirname "${SNAPSHOT_FILE}")"
    capture_status >"${SNAPSHOT_FILE}"
    ;;
  verify)
    [[ -f "${SNAPSHOT_FILE}" ]] ||
      fail "no snapshot at ${SNAPSHOT_FILE}; run --snapshot before the command under test"

    after="$(mktemp "${TMPDIR:-/tmp}/worktree-after.XXXXXX")"
    trap 'rm -f "${after}"' EXIT
    capture_status >"${after}"

    if diff -q "${SNAPSHOT_FILE}" "${after}" >/dev/null 2>&1; then
      echo "OK   working tree unchanged by the command under test"
      exit 0
    fi

    echo "FAIL the command under test changed the working tree" >&2
    echo "" >&2
    # Lines only in the "after" capture are what the run introduced; lines only
    # in the snapshot are what it removed.
    diff "${SNAPSHOT_FILE}" "${after}" | while IFS= read -r line; do
      case "${line}" in
        ">"*) echo "     introduced: ${line#> }" >&2 ;;
        "<"*) echo "     removed:    ${line#< }" >&2 ;;
      esac
    done
    echo "" >&2
    echo "     A test is writing outside its temp directory. Fix the test, not this check." >&2
    exit 1
    ;;
esac
