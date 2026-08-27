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

  cat >"${SUITE}" <<'EOF'
setup() {
  source "${TARGET}"
}

@test "positive" { sample_is_positive 5; }
@test "negative is not positive" { ! sample_is_positive -1; }
@test "even" { sample_is_even 4; }
@test "odd is not even" { ! sample_is_even 3; }
@test "in range" { sample_in_range 5; }
@test "out of range" { ! sample_in_range 11; }
@test "named" { sample_is_named sample; }
@test "not named" { ! sample_is_named other; }
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

@test "a completed run reconciles its bookkeeping and reports a score" {
  run "${RUNNER}" --script "${TARGET}" --bats "${SUITE}" \
    --report-dir "${BATS_TEST_TMPDIR}/clean-report" \
    --timeout 30 --max-mutants 4 --execute --no-fail

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Done in"* ]]
  run cmp -s "${TARGET}" "${PRISTINE}"
  [ "${status}" -eq 0 ]
}
