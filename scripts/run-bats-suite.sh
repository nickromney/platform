#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

BATS_BIN="${BATS_BIN:-bats}"
RUN_BATS_SHARDS="${RUN_BATS_SHARDS:-${REPO_ROOT}/scripts/run-bats-shards.sh}"
# bats resolves the binary itself via BATS_PARALLEL_BINARY_NAME/--parallel-binary-name,
# so pointing this at an alternative has to tell bats too -- otherwise the check
# here passes and bats still goes looking for "parallel". GNU parallel is the only
# implementation verified against this suite; the hook exists because GNU parallel
# is not installable through mise (no registry entry, no asdf plugin, no aqua
# package, and GNU hosts releases outside GitHub), so a host without brew/pacman/apt
# has no managed route to it.
PARALLEL_BIN="${PARALLEL_BIN:-parallel}"
INSTALL_HINTS_SCRIPT="${INSTALL_HINTS_SCRIPT:-${REPO_ROOT}/scripts/install-tool-hints.sh}"
JOBS="${BATS_JOBS:-auto}"
# Leave headroom: bats forks a shell per file and the box is usually also
# running an editor and a container runtime.
MAX_AUTO_JOBS="${BATS_MAX_AUTO_JOBS:-8}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<EOF
Usage: ${0##*/} [--jobs auto|off|N] [--shards N] [--tests-dir DIR] [--plan] [--dry-run] [--execute] -- <bats file>...

Run a Bats suite, in parallel when GNU parallel is available.

The suite is 1084 tests and took 715s serially, on a 10-core box that was doing
nothing else. That is long enough that the lefthook pre-push gate could not
finish before GitHub closed the SSH connection, so the push failed even when the
tests passed.

--jobs auto (the default) uses parallel when it is installed and falls back to a
serial run when it is not, so a host without parallel still gets a correct -- if
slower -- result. An explicit --jobs N is a demand rather than a preference: if
parallel is missing it is an error, because \`bats --jobs N\` without parallel
runs ZERO tests. It does exit 1, so it cannot pass silently, but the failure
reads as "Executed 0 instead of expected N" rather than "install parallel", and
that is worth naming before the run instead of after it.

--shards N splits one tests directory into balanced --filter shards (used by
kind test-bats). --plan prints that shard plan without running.

Options:
  --jobs VALUE       auto (default), off/1 for serial, or an explicit job count
  --shards N         shard a --tests-dir instead of running the file list
  --tests-dir DIR    directory of .bats files for --shards
  --plan             print the shard plan only
$(shell_cli_standard_options)
EOF
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

detect_cpus() {
  if command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
    sysctl -n hw.ncpu
    return 0
  fi
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi
  printf '%s\n' 1
}

have_parallel() {
  command -v "${PARALLEL_BIN}" >/dev/null 2>&1
}

print_parallel_hint() {
  [[ -x "${INSTALL_HINTS_SCRIPT}" ]] || return 0
  echo "" >&2
  echo "Install hints:" >&2
  "${INSTALL_HINTS_SCRIPT}" --execute --plain parallel | sed 's/^/  /' >&2
}

shell_cli_init_standard_flags
bats_files=()
SHARDS=""
TESTS_DIR=""
PLAN_ONLY=0
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --jobs)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--jobs"; exit 1; }
      JOBS="$2"
      shift 2
      ;;
    --shards)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--shards"; exit 1; }
      SHARDS="$2"
      shift 2
      ;;
    --tests-dir)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--tests-dir"; exit 1; }
      TESTS_DIR="$2"
      shift 2
      ;;
    --plan)
      PLAN_ONLY=1
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        bats_files+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      bats_files+=("$1")
      shift
      ;;
  esac
done

if [[ -n "${SHARDS}" ]]; then
  shard_args=(--shards "${SHARDS}")
  [[ -n "${TESTS_DIR}" ]] && shard_args+=(--tests-dir "${TESTS_DIR}")
  [[ "${PLAN_ONLY}" -eq 1 ]] && shard_args+=(--plan)
  shell_cli_maybe_execute_or_preview_summary usage \
    "would shard Bats tests with ${SHARDS} shard(s)"
  exec "${RUN_BATS_SHARDS}" "${shard_args[@]}"
fi

shell_cli_maybe_execute_or_preview_summary usage \
  "would run ${#bats_files[@]} Bats file(s) with --jobs ${JOBS}"

[[ "${#bats_files[@]}" -gt 0 ]] || fail "no Bats files given"
command -v "${BATS_BIN}" >/dev/null 2>&1 || fail "${BATS_BIN} not found in PATH"
export BATS_LIB_PATH="${REPO_ROOT}/tests${BATS_LIB_PATH:+:${BATS_LIB_PATH}}"

resolved_jobs=1
case "${JOBS}" in
  off | 1)
    resolved_jobs=1
    ;;
  auto)
    if have_parallel; then
      cpus="$(detect_cpus)"
      resolved_jobs=$(( cpus > 2 ? cpus - 2 : 1 ))
      [[ "${resolved_jobs}" -le "${MAX_AUTO_JOBS}" ]] || resolved_jobs="${MAX_AUTO_JOBS}"
    else
      echo "WARN GNU parallel not found; running the suite serially" >&2
      print_parallel_hint
      resolved_jobs=1
    fi
    ;;
  *[!0-9]* | "")
    fail "invalid --jobs value '${JOBS}'; expected auto, off, or a positive integer"
    ;;
  *)
    resolved_jobs="${JOBS}"
    # An explicit count is a demand. Refusing here is the whole point: bats would
    # otherwise report "Executed 0 instead of expected N", which names the
    # symptom and not the cause.
    if [[ "${resolved_jobs}" -gt 1 ]] && ! have_parallel; then
      echo "FAIL --jobs ${resolved_jobs} needs GNU parallel, which is not in PATH." >&2
      echo "     bats would run ZERO tests. Install parallel, or use --jobs off." >&2
      print_parallel_hint
      exit 1
    fi
    ;;
esac

# Files that mutate state shared with the rest of the repo, so they cannot run
# beside anything else. This is a containment list, not an approval: each entry
# is a test writing outside its own BATS_TEST_TMPDIR, which makes it
# order-dependent even in a serial run and leaves debris if it aborts mid-test.
#
# Measured 2026-08-16 by running the suite with --jobs and diffing against the
# serial result -- these four failed, the other 141 files did not.
#
#   platform-workflow      writes a Terraform lock into terraform/.run/ in the
#                          real repo, then rm -f's it
#   release-workflow       creates a real annotated git tag in the real repo
#   app-layout-consistency  runs make against the real tree
#   make-target-surfaces    runs make against the real tree
#   apps-makefile           runs make against the real tree
#
# Added 2026-08-26, after the suite started running in parallel by default:
#
#   cilium-module-renderers runs render-category.sh --execute, which rewrites
#                           the checked-in policy files under
#                           cluster-policies/cilium/, then diffs against them.
#                           More than ten other files read that same tree, so a
#                           reader can catch a file mid-rewrite. It does not
#                           reproduce at `bats -j 8` on the file alone -- the
#                           collision is with other files, not within this one,
#                           which is why it showed up only in a full gate.
#
# Isolating them properly is the fix; running them serially is the stopgap.
SERIAL_ONLY_FILES="${BATS_SERIAL_ONLY_FILES:-tests/platform-workflow.bats
tests/release-workflow.bats
tests/app-layout-consistency.bats
tests/make-target-surfaces.bats
tests/apps-makefile.bats
kubernetes/kind/tests/cilium-module-renderers.bats}"

is_serial_only() {
  printf '%s\n' "${SERIAL_ONLY_FILES}" | grep -qxF "$1"
}

if [[ "${resolved_jobs}" -le 1 ]]; then
  echo "INFO running ${#bats_files[@]} Bats file(s) serially"
  exec "${BATS_BIN}" "${bats_files[@]}"
fi

parallel_files=()
serial_files=()
for file in "${bats_files[@]}"; do
  if is_serial_only "${file}"; then
    serial_files+=("${file}")
  else
    parallel_files+=("${file}")
  fi
done

rc=0
if [[ "${#parallel_files[@]}" -gt 0 ]]; then
  echo "INFO running ${#parallel_files[@]} Bats file(s) across ${resolved_jobs} job(s)"
  bats_parallel_args=(--jobs "${resolved_jobs}")
  if [[ "${PARALLEL_BIN}" != "parallel" ]]; then
    bats_parallel_args+=(--parallel-binary-name "${PARALLEL_BIN}")
  fi
  "${BATS_BIN}" "${bats_parallel_args[@]}" "${parallel_files[@]}" || rc=$?
fi

if [[ "${#serial_files[@]}" -gt 0 ]]; then
  echo "INFO running ${#serial_files[@]} shared-state Bats file(s) serially"
  "${BATS_BIN}" "${serial_files[@]}" || rc=$?
fi

exit "${rc}"
