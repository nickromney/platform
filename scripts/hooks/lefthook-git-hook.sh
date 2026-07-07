#!/bin/sh

if [ "${LEFTHOOK_VERBOSE:-}" = "1" ] || [ "${LEFTHOOK_VERBOSE:-}" = "true" ]; then
  set -x
fi

hook_name="$(basename "$0")"

if [ "${LEFTHOOK:-}" = "0" ]; then
  exit 0
fi

warn_skip() {
  echo "WARN lefthook ${hook_name}: $*" >&2
  echo "WARN lefthook ${hook_name}: skipping hook so Git worktree operations are not blocked" >&2
  echo "WARN lefthook ${hook_name}: retry from the main checkout after repairing Git config, or use make hooks" >&2
}

if ! command -v lefthook >/dev/null 2>&1; then
  warn_skip "lefthook not found in PATH"
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  warn_skip "Git does not report an active work tree"
  exit 0
fi

if ! git rev-parse --path-format=absolute --show-toplevel --git-path hooks --git-path info --git-dir >/dev/null 2>&1; then
  warn_skip "lefthook Git metadata probe fails in this checkout"
  exit 0
fi

tmp_output="${TMPDIR:-/tmp}/lefthook-${hook_name}-$$.log"
trap 'rm -f "${tmp_output}"' EXIT HUP INT TERM

lefthook run "${hook_name}" "$@" >"${tmp_output}" 2>&1
status=$?
cat "${tmp_output}"

if [ "${status}" -eq 128 ]; then
  if grep -F "must be run in a work tree" "${tmp_output}" >/dev/null 2>&1 ||
    grep -F "git rev-parse --path-format=absolute --show-toplevel --git-path hooks --git-path info --git-dir" "${tmp_output}" >/dev/null 2>&1; then
    warn_skip "lefthook failed while resolving Git worktree metadata"
    exit 0
  fi
fi

exit "${status}"
