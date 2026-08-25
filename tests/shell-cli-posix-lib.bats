#!/usr/bin/env bash
#
# First oracle for scripts/lib/shell-cli-posix.sh, the POSIX sh twin of
# scripts/lib/shell-cli.sh used by entrypoints that cannot assume bash.
#
# Every fixture runs under /bin/sh rather than bash, because running the POSIX
# library under bash would not test the thing that makes it separate.
#
# NOTE for mutation runs: the runner's default oracle glob for shell-cli.sh is
# tests/shell-cli*.bats, which also matches this file. Name the suite
# explicitly when mutating either library:
#   scripts/mutation-test.sh --script scripts/lib/shell-cli-posix.sh \
#     --bats tests/shell-cli-posix-lib.bats --execute

setup() {
  local root
  root="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)"
  export LIB="${root}/scripts/lib/shell-cli-posix.sh"
}

write_preview_script() {
  cat >"${BATS_TEST_TMPDIR}/demo" <<EOF
#!/bin/sh
set -eu
. '${LIB}'
usage() { printf 'USAGE\n'; }
preview() { printf 'PREVIEW\n'; }
shell_cli_parse_standard_only usage "\$@" || exit 1
shell_cli_maybe_execute_or_preview usage preview
printf 'BODY\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/demo"
}

write_no_args_script() {
  cat >"${BATS_TEST_TMPDIR}/demo2" <<EOF
#!/bin/sh
set -eu
. '${LIB}'
usage() { printf 'USAGE\n'; }
shell_cli_handle_standard_no_args usage "would do the thing" "\$@"
printf 'BODY\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/demo2"
}

@test "posix script_name prefers the override and reports success" {
  run /bin/sh -c "SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; . '${LIB}'; shell_cli_script_name; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "demo" ]
  [ "${lines[1]}" = "st=0" ]
}

@test "posix diagnostics name the script and go to stderr" {
  run /bin/sh -c "SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; . '${LIB}'; shell_cli_unknown_flag --nope 2>&1 1>/dev/null"
  [ "${output}" = "demo: unknown flag: --nope" ]

  run /bin/sh -c "SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; . '${LIB}'; shell_cli_unexpected_arg stray 2>&1 1>/dev/null"
  [ "${output}" = "demo: unexpected argument: stray" ]

  run /bin/sh -c "SHELL_CLI_SCRIPT_NAME_OVERRIDE=demo; . '${LIB}'; shell_cli_missing_value --out 2>&1 1>/dev/null"
  [ "${output}" = "demo: missing value for --out" ]
}

@test "posix handle_standard_flag claims the flags it owns" {
  run /bin/sh -c ". '${LIB}'; shell_cli_init_standard_flags; shell_cli_handle_standard_flag usage --dry-run; printf 'st=%s dry=%s exec=%s' \"\$?\" \"\${SHELL_CLI_DRY_RUN}\" \"\${SHELL_CLI_EXECUTE}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0 dry=1 exec=0" ]

  run /bin/sh -c ". '${LIB}'; shell_cli_init_standard_flags; shell_cli_handle_standard_flag usage --execute; printf 'st=%s dry=%s exec=%s' \"\$?\" \"\${SHELL_CLI_DRY_RUN}\" \"\${SHELL_CLI_EXECUTE}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0 dry=0 exec=1" ]
}

@test "posix handle_standard_flag disowns anything else" {
  # The nonzero return is how parse_standard_only knows to fall through to its
  # own case arms, so it is contract, not an error path.
  run /bin/sh -c ". '${LIB}'; shell_cli_init_standard_flags; shell_cli_handle_standard_flag usage --something; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=1" ]
}

@test "posix parse_standard_only stops flag parsing at a bare double dash" {
  run /bin/sh -c ". '${LIB}'; usage() { :; }; shell_cli_parse_standard_only usage -- --looks-like-a-flag tail; printf 'st=%s args=%s' \"\$?\" \"\${SHELL_CLI_ARGS}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0 args=--looks-like-a-flag tail" ]
}

@test "posix parse_standard_only rejects an unknown flag" {
  run /bin/sh -c ". '${LIB}'; usage() { :; }; shell_cli_parse_standard_only usage --nope; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"unknown flag: --nope"* ]]
  [[ "${output}" == *"st=1"* ]]
}

@test "posix dry-run previews without usage and without the body" {
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo" --dry-run

  [ "${status}" -eq 0 ]
  [ "${output}" = "PREVIEW" ]
}

@test "posix execute runs the body instead of previewing" {
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "BODY" ]
}

@test "posix no flags prints usage and preview and stops short of the body" {
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo"

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "USAGE" ]
  [ "${lines[1]}" = "PREVIEW" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "posix help prints usage and exits zero" {
  write_preview_script

  run "${BATS_TEST_TMPDIR}/demo" --help

  [ "${status}" -eq 0 ]
  [ "${output}" = "USAGE" ]
}

@test "posix handle_standard_no_args exits on an unexpected argument" {
  write_no_args_script

  run "${BATS_TEST_TMPDIR}/demo2" --execute stray

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"unexpected argument: stray"* ]]
  [[ "${output}" != *"BODY"* ]]
}

@test "posix handle_standard_no_args runs the body for a clean execute" {
  write_no_args_script

  run "${BATS_TEST_TMPDIR}/demo2" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "BODY" ]
}

@test "posix handle_standard_no_args summarises under dry-run" {
  write_no_args_script

  run "${BATS_TEST_TMPDIR}/demo2" --dry-run

  [ "${status}" -eq 0 ]
  [ "${output}" = "INFO dry-run: would do the thing" ]
}

@test "posix standard_options lists the flags the library actually handles" {
  # The bash library also advertises --shell-entrypoint-descriptor; this one
  # does not implement it, so it must not claim it either.
  run /bin/sh -c ". '${LIB}'; shell_cli_standard_options"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--dry-run"* ]]
  [[ "${output}" == *"--execute"* ]]
  [[ "${output}" == *"-h, --help"* ]]
  [[ "${output}" != *"--shell-entrypoint-descriptor"* ]]
}

@test "posix parse_standard_only ends cleanly when the flags run out" {
  # Kills BOUNDARY_CHECK at shell-cli-posix.sh:71. Under `-ge 0` the loop runs
  # one more time after the last argument is shifted away and dereferences "$1"
  # when there is no $1 left. Without `set -u` that is an empty string that
  # falls out through the default case, which is why this only bites a caller
  # that sets nounset -- and every entrypoint using this library does.
  cat >"${BATS_TEST_TMPDIR}/demo4" <<EOF
#!/bin/sh
set -eu
. '${LIB}'
usage() { printf 'USAGE\n'; }
preview() { printf 'PREVIEW\n'; }
shell_cli_parse_standard_only usage "\$@" || exit 1
shell_cli_maybe_execute_or_preview usage preview
printf 'BODY\n'
EOF
  chmod +x "${BATS_TEST_TMPDIR}/demo4"

  run /bin/sh "${BATS_TEST_TMPDIR}/demo4" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "BODY" ]
}
