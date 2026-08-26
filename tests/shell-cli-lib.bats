#!/usr/bin/env bash
#
# Unit oracle for scripts/lib/shell-cli.sh.
#
# tests/audit-shell-scripts.bats exercises this library indirectly, by running
# every entrypoint in the repo through it. That makes it a slow oracle and a
# blunt one: it proves the helpers work end to end without ever asserting what
# any single helper returns. This suite drives them directly.

setup() {
  local root
  root="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)"
  export LIB="${root}/scripts/lib/shell-cli.sh"
}

# A minimal entrypoint using the preview/execute pair, for the branches that
# end in `exit` and so cannot be observed from inside the calling shell.
write_preview_script() {
  cat >"${BATS_TEST_TMPDIR}/demo.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB}'
usage() { printf 'USAGE\n'; }
preview() { printf 'PREVIEW\n'; }
shell_cli_parse_standard_only usage "\$@" || exit 1
shell_cli_maybe_execute_or_preview usage preview
printf 'BODY\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/demo.sh"
}

# The no-args variant, which is what most entrypoints in this repo call.
write_no_args_script() {
  cat >"${BATS_TEST_TMPDIR}/demo2.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '${LIB}'
usage() { printf 'USAGE\n'; }
shell_cli_handle_standard_no_args usage "would do the thing" "\$@"
printf 'BODY\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/demo2.sh"
}

@test "script_name reports success when the override is used" {
  # Kills RETURN_CODE at shell-cli.sh:7. Every caller reads the name through
  # "$(shell_cli_script_name)", so a nonzero return is invisible there -- but
  # not to an errexit caller that calls it as a plain statement.
  run bash -c "SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; source '${LIB}'; shell_cli_script_name; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "demo" ]
  [ "${lines[1]}" = "st=0" ]
}

@test "print_command separates arguments without a leading space" {
  # Kills NUMERIC_COMPARE at shell-cli.sh:45. `first` starts at 1, so inverting
  # the test emits the separator before the first argument and drops it between
  # every later pair: `a b` becomes ` ab`.
  run bash -c "source '${LIB}'; shell_cli_print_command make lint 'two words'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "make lint two\\ words" ]
}

@test "parse_standard_only stops flag parsing at a bare double dash" {
  # Kills ARITH_STEP at shell-cli.sh:141. Rewritten to `++)` the end-of-flags
  # marker no longer matches, falls through to the `-*` arm, and `--` is
  # rejected as an unknown flag instead of separating flags from operands.
  run bash -c "source '${LIB}'; usage() { :; }; shell_cli_parse_standard_only usage -- --looks-like-a-flag tail; printf 'st=%s count=%s args=%s' \"\$?\" \"\${SHELL_CLI_ARG_COUNT}\" \"\${SHELL_CLI_ARGS[*]}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0 count=2 args=--looks-like-a-flag tail" ]
}

@test "parse_standard_only rejects an unknown flag" {
  # Kills RETURN_CODE at shell-cli.sh:147. The message already goes to stderr;
  # the status is what makes the caller's `|| exit 1` fire. Flipped to 0 an
  # unrecognised flag is silently accepted and the script runs anyway.
  run bash -c "source '${LIB}'; usage() { :; }; shell_cli_parse_standard_only usage --nope; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"unknown flag: --nope"* ]]
  [[ "${output}" == *"st=1"* ]]
}

@test "dry-run previews without printing usage and without running the body" {
  # Kills NUMERIC_COMPARE at shell-cli.sh:164. Inverted, --dry-run falls past
  # its own branch into the not-executing branch, which prints usage as well as
  # the preview. The distinction matters: --dry-run is the deliberate ask, so
  # it answers with the preview alone.
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo.sh" --dry-run

  [ "${status}" -eq 0 ]
  [ "${output}" = "PREVIEW" ]
}

@test "execute runs the body instead of previewing" {
  # Kills NUMERIC_COMPARE at shell-cli.sh:169. Inverted, --execute takes the
  # not-executing branch: the script prints usage and a preview and exits 0
  # without ever running its body, while still reporting success.
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo.sh" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "BODY" ]
}

@test "no flags prints usage and preview and stops short of the body" {
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo.sh"

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "USAGE" ]
  [ "${lines[1]}" = "PREVIEW" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "require_no_args accepts an empty argument list" {
  # Kills BOUNDARY_CHECK at shell-cli.sh:196. Under `-ge 0` the zero-argument
  # case enters the rejection branch and complains about an unexpected argument
  # that is the empty string, so every no-args entrypoint refuses to run.
  run bash -c "source '${LIB}'; SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; shell_cli_require_no_args; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]
}

@test "require_no_args rejects a stray argument" {
  # Kills RETURN_CODE at shell-cli.sh:198.
  run bash -c "source '${LIB}'; SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; shell_cli_require_no_args stray; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"unexpected argument: stray"* ]]
  [[ "${output}" == *"st=1"* ]]
}

@test "handle_standard_no_args exits when given an unexpected argument" {
  # Kills LOGICAL_AND_OR at shell-cli.sh:209. ANDed, the `exit 1` fires only
  # when the argument check *passed*, so a rejected argument no longer stops
  # anything: the script prints its complaint to stderr and then runs the body
  # anyway, reporting success.
  write_no_args_script

  run "${BATS_TEST_TMPDIR}/demo2.sh" --execute stray

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"unexpected argument: stray"* ]]
  [[ "${output}" != *"BODY"* ]]
}

@test "handle_standard_no_args runs the body for a clean execute" {
  write_no_args_script

  run "${BATS_TEST_TMPDIR}/demo2.sh" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "BODY" ]
}

@test "handle_standard_no_args summarises under dry-run" {
  write_no_args_script

  run "${BATS_TEST_TMPDIR}/demo2.sh" --dry-run

  [ "${status}" -eq 0 ]
  [ "${output}" = "INFO dry-run: would do the thing" ]
}

@test "handle_standard_no_args survives a zero-argument run on bash 3.2" {
  # Kills BOUNDARY_CHECK at shell-cli.sh:208. On bash 4.4 and newer the guard
  # looks redundant -- calling require_no_args with an empty array is harmless,
  # so `-ge 0` behaves identically and the mutant reads as an equivalent. On
  # bash 3.2, which is what /bin/bash still is on macOS and what `make
  # lint-bash32` exists to protect, expanding "${empty[@]}" under `set -u` is an
  # unbound-variable error. The guard is what stops every no-args entrypoint
  # from dying on its own success path there.
  #
  # Run explicitly under /bin/bash, matching the convention in
  # tests/check-bash32-compat.bats; on a newer /bin/bash this still passes, it
  # just stops being the interesting case.
  cat >"${BATS_TEST_TMPDIR}/demo3" <<EOF
#!/bin/bash
set -euo pipefail
source '${LIB}'
usage() { printf 'USAGE\n'; }
shell_cli_handle_standard_no_args usage "would do the thing" "\$@"
printf 'BODY\n'
EOF

  run /bin/bash "${BATS_TEST_TMPDIR}/demo3" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "BODY" ]
}
