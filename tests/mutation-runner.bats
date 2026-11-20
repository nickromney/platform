#!/usr/bin/env bats
#
# Interrupt behaviour for scripts/mutation-test.sh.
#
# The runner swaps a mutant over the real working-tree file for the duration of
# each suite run, so what it does when signalled is a property worth testing
# rather than assuming. It used to trap INT/TERM with a handler that restored the
# original and returned, which handed control straight back to the loop: the next
# mutant was copied over the target and the run carried on. Measured before the
# fix, SIGTERM after four mutants was followed by seven more and the run reached
# its normal end.
#
# The two tests below assert different halves, and the split matters. Signalling
# a run that then completes normally still ends with a restored file, so "the
# target is clean afterwards" does NOT catch the old behaviour on its own -- it
# was written that way first and passed against the bug. The damage needs the
# sequence a supervisor or tool timeout actually produces: TERM, ignored, then
# KILL landing while a mutant is on disk.
#
# Everything happens inside BATS_TEST_TMPDIR, target included. A test for a tool
# that mutates files has no business pointing it at the real tree.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export RUNNER="${REPO_ROOT}/scripts/mutation-test.sh"

  export FIXTURE_DIR="${BATS_TEST_TMPDIR}/fixture"
  export TARGET="${FIXTURE_DIR}/sample.sh"
  export PRISTINE="${BATS_TEST_TMPDIR}/sample.pristine"
  export SUITE="${FIXTURE_DIR}/sample.bats"
  export RUN_LOG="${BATS_TEST_TMPDIR}/run.log"
  mkdir -p "${FIXTURE_DIR}"

  # Enough mutable constructs to give the loop many iterations. Length comes
  # from the number of mutants rather than from sleeping in the oracle: the
  # window to signal in is just as wide, and the suite stays cheap enough to sit
  # in the gate.
  cat >"${TARGET}" <<'EOF'
#!/usr/bin/env bash

sample_is_positive() {
  local n="$1"
  [ "${n}" -gt 0 ] && return 0
  return 1
}

sample_is_even() {
  local n="$1"
  [ "$(( n % 2 ))" -eq 0 ] && return 0
  return 1
}

sample_in_range() {
  local n="$1"
  [ "${n}" -ge 0 ] && [ "${n}" -le 10 ] && return 0
  return 1
}

sample_is_named() {
  local name="$1"
  [ "${name}" == "sample" ] && return 0
  return 1
}
EOF
  cp "${TARGET}" "${PRISTINE}"

  # Bats 1.10 (the devcontainer's apt build) rewrites every line that starts
  # with @test before running a file -- heredoc bodies included -- which would
  # leave this fixture with no tests at all. Write @TEST and swap it on disk.
  sed 's/^@TEST /@test /' >"${SUITE}" <<'EOF'
setup() {
  source "${TARGET}"
}

@TEST "positive" { sample_is_positive 5; }
@TEST "negative is not positive" { ! sample_is_positive -1; }
@TEST "even" { sample_is_even 4; }
@TEST "odd is not even" { ! sample_is_even 3; }
@TEST "in range" { sample_in_range 5; }
@TEST "out of range" { ! sample_in_range 11; }
@TEST "named" { sample_is_named sample; }
@TEST "not named" { ! sample_is_named other; }
# Pace each mutant's suite run. Without it the whole loop finishes in well under
# a second on Linux, before the signal tests can interrupt it mid-run.
@TEST "pace" {
  if ! cmp -s "${TARGET}" "${PRISTINE}"; then
    [ -z "${SLOW_STARTED:-}" ] || touch "${SLOW_STARTED}"
    if [ -n "${TIMEOUT_CHILD_MARKER:-}" ]; then
      bash -c 'trap "" TERM; bash -c "trap \"\" TERM; sleep 6; touch \"\$1\"" _ "$2" & wait; touch "$1"' _ \
        "${TIMEOUT_CHILD_MARKER}" "${TIMEOUT_GRANDCHILD_MARKER}"
    else
      sleep "${MUTANT_PACE_SECONDS:-${PACE_SECONDS:-0.3}}"
    fi
    [ -z "${SLOW_FINISHED:-}" ] || touch "${SLOW_FINISHED}"
  else
    sleep "${PACE_SECONDS:-0.3}"
  fi
}
EOF
}

teardown() {
  if [ -n "${RUN_PID:-}" ] && kill -0 "${RUN_PID}" 2>/dev/null; then
    kill -KILL "${RUN_PID}" 2>/dev/null || true
  fi
}

# Starts a run and blocks until the mutation loop has processed at least one
# mutant, so a signal cannot land before the loop begins.
start_run_and_wait_for_loop() {
  "${RUNNER}" --script "${TARGET}" --bats "${SUITE}" \
    --report-dir "${BATS_TEST_TMPDIR}/report" \
    --timeout 30 --execute >"${RUN_LOG}" 2>&1 &
  RUN_PID=$!

  local waited=0
  while [ "${waited}" -lt 120 ]; do
    grep -qE '(killed|SURVIVED)' "${RUN_LOG}" 2>/dev/null && return 0
    kill -0 "${RUN_PID}" 2>/dev/null || return 1
    sleep 1
    waited=$((waited + 1))
  done

  return 1
}

wait_for_exit() {
  local waited=0
  while kill -0 "${RUN_PID}" 2>/dev/null && [ "${waited}" -lt 60 ]; do
    sleep 1
    waited=$((waited + 1))
  done
}

@test "SIGTERM stops the run instead of restoring and continuing" {
  start_run_and_wait_for_loop

  # Guards against a vacuous pass: with the run already finished there would be
  # nothing to interrupt and everything below would hold trivially.
  kill -0 "${RUN_PID}"

  kill -TERM "${RUN_PID}"
  wait_for_exit

  run kill -0 "${RUN_PID}"
  [ "${status}" -ne 0 ]

  # The discriminator, and deterministic rather than timing-based. Under the old
  # trap the signal was ignored and the run reached its normal end, which prints
  # this line. Aborting means it never gets there.
  run grep -c 'Done in' "${RUN_LOG}"
  [ "${output}" -eq 0 ]
}

@test "TERM then KILL leaves no mutant in the target" {
  # The sequence that actually does the damage, and the reason this is not
  # folded into the test above. A signalled run that completes normally restores
  # the file on its way out, so asserting only "the target is clean" passes
  # against the old behaviour. Here the KILL arrives while the old code would
  # still be working through mutants.
  start_run_and_wait_for_loop
  kill -0 "${RUN_PID}"

  kill -TERM "${RUN_PID}"
  sleep 2
  kill -KILL "${RUN_PID}" 2>/dev/null || true
  wait_for_exit

  run cmp -s "${TARGET}" "${PRISTINE}"
  [ "${status}" -eq 0 ]
}

@test "TERM stops a slow suite before restoring the target" {
  export PACE_SECONDS=4 SLOW_STARTED="${BATS_TEST_TMPDIR}/slow-started" SLOW_FINISHED="${BATS_TEST_TMPDIR}/slow-finished"
  "${RUNNER}" --script "${TARGET}" --bats "${SUITE}" \
    --report-dir "${BATS_TEST_TMPDIR}/report" --timeout 30 --execute >"${RUN_LOG}" 2>&1 &
  RUN_PID=$!
  local waited=0
  while [ ! -f "${SLOW_STARTED}" ] && [ "${waited}" -lt 120 ]; do
    kill -0 "${RUN_PID}"
    sleep 1
    waited=$((waited + 1))
  done
  [ -f "${SLOW_STARTED}" ]
  kill -TERM "${RUN_PID}"
  sleep 2
  kill -KILL "${RUN_PID}" 2>/dev/null || true
  wait_for_exit
  run cmp -s "${TARGET}" "${PRISTINE}"
  [ "${status}" -eq 0 ]
  sleep 3
  [ ! -e "${SLOW_FINISHED}" ]
}

@test "suite timeouts still count as killed mutants" {
  export TIMEOUT_CHILD_MARKER="${BATS_TEST_TMPDIR}/timeout-child" TIMEOUT_GRANDCHILD_MARKER="${BATS_TEST_TMPDIR}/timeout-grandchild"
  run "${RUNNER}" --script "${TARGET}" --bats "${SUITE}" \
    --report-dir "${BATS_TEST_TMPDIR}/timeout-report" --timeout 3 --max-mutants 1 --execute --no-fail
  if [ "${status}" -ne 0 ]; then printf "%s\n" "${output}" >&2; fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"killed (timeout)"* ]]
  run cmp -s "${TARGET}" "${PRISTINE}"
  [ "${status}" -eq 0 ]
  sleep 7
  [ ! -e "${TIMEOUT_CHILD_MARKER}" ]
  [ ! -e "${TIMEOUT_GRANDCHILD_MARKER}" ]
}

run_resistant_direct_suite() {
  local mode="$1" bin_dir="${BATS_TEST_TMPDIR}/bin-${1}" name command_path
  mkdir -p "${bin_dir}"
  for name in bash perl awk basename cat cmp cp date diff dirname grep head mkdir rm sed sleep touch tr wc; do
    command_path="$(command -v "${name}")"
    ln -s "${command_path}" "${bin_dir}/${name}"
  done
  if [ "${mode}" = timeout ]; then
    command_path="$(command -v timeout || command -v gtimeout)"
    ln -s "${command_path}" "${bin_dir}/timeout"
  fi
  cat >"${bin_dir}/bats" <<'EOF'
#!/usr/bin/env bash
if cmp -s "${TARGET}" "${PRISTINE}"; then exit 0; fi
date +%s >"${DIRECT_STARTED}"
trap "" TERM
bash -c 'trap "" TERM; sleep 6; touch "$1"' _ "${DIRECT_GRANDCHILD}" &
sleep 6
touch "${DIRECT_FINISHED}"
EOF
  chmod +x "${bin_dir}/bats"
  export DIRECT_STARTED="${BATS_TEST_TMPDIR}/direct-started-${mode}"
  export DIRECT_FINISHED="${BATS_TEST_TMPDIR}/direct-finished-${mode}"
  export DIRECT_GRANDCHILD="${BATS_TEST_TMPDIR}/direct-grandchild-${mode}"
  run env PATH="${bin_dir}" "${RUNNER}" --script "${TARGET}" --bats "${SUITE}" \
    --report-dir "${BATS_TEST_TMPDIR}/direct-report-${mode}" --timeout 1 --max-mutants 1 --execute --no-fail
  local finished started
  finished="$(date +%s)"
  if [ "${status}" -ne 0 ]; then printf '%s\n' "${output}" >&2; fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"killed (timeout)"* ]]
  [ -f "${DIRECT_STARTED}" ]
  started="$(cat "${DIRECT_STARTED}")"
  printf 'direct %s elapsed: %s seconds\n' "${mode}" "$((finished - started))" >&2
  [ "$((finished - started))" -le 3 ]
  run cmp -s "${TARGET}" "${PRISTINE}"
  [ "${status}" -eq 0 ]
  sleep 7
  [ ! -e "${DIRECT_FINISHED}" ]
  [ ! -e "${DIRECT_GRANDCHILD}" ]
}

@test "hard deadline kills a TERM-resistant direct suite with timeout available" {
  run_resistant_direct_suite timeout
}

@test "hard deadline kills a TERM-resistant direct suite without timeout utility" {
  run_resistant_direct_suite fallback
}

@test "a completed run reconciles its bookkeeping and reports a score" {
  run "${RUNNER}" --script "${TARGET}" --bats "${SUITE}" \
    --report-dir "${BATS_TEST_TMPDIR}/clean-report" \
    --timeout 30 --max-mutants 4 --execute --no-fail

  if [ "${status}" -ne 0 ]; then
    printf 'mutation runner status %s:\n%s\n' "${status}" "${output}" >&2
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Done in"* ]]
  run cmp -s "${TARGET}" "${PRISTINE}"
  [ "${status}" -eq 0 ]
}
