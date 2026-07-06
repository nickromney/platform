#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIXTURE="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FIXTURE}/scripts/lib" "${FIXTURE}/kubernetes/kind/tests"
  cp "${REPO_ROOT}/scripts/run-bats-shards.sh" "${FIXTURE}/scripts/"
  cp "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${FIXTURE}/scripts/lib/"
  RUNNER="${FIXTURE}/scripts/run-bats-shards.sh"
  mkdir -p "${FIXTURE}/.run/bats-shards/kind"
  printf 'preserve\n' > "${FIXTURE}/.run/bats-shards/kind/sentinel"
  export CALL_LOG="${BATS_TEST_TMPDIR}/calls"
  cat > "${BATS_TEST_TMPDIR}/bats-probe" <<'PROBE'
#!/bin/bash
printf 'called\n' >> "$CALL_LOG"
exit 99
PROBE
  chmod +x "${BATS_TEST_TMPDIR}/bats-probe"
  export BATS="${BATS_TEST_TMPDIR}/bats-probe"
}

@test "shard default and dry-run preserve logs and never launch Bats" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *'INFO dry-run:'* ]] || return 1
  run "$RUNNER" --execute --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$CALL_LOG" ]
  [ "$(cat "${FIXTURE}/.run/bats-shards/kind/sentinel")" = preserve ]
}

@test "shard plan uses disposable planning files and preserves prior logs" {
  run "$RUNNER" --plan --shards 2
  [ "$status" -eq 0 ]
  [[ "$output" == *'total: 0 tests'* ]] || return 1
  [ ! -e "$CALL_LOG" ]
  [ -f "${FIXTURE}/.run/bats-shards/kind/sentinel" ]
}

@test "shard descriptor and argument errors do not launch Bats" {
  run "$RUNNER" --shell-entrypoint-descriptor
  [ "$status" -eq 0 ]
  [[ "$output" == *'"default_mode":"dry-run"'* ]] || return 1
  run "$RUNNER" --execute --shards 0
  [ "$status" -ne 0 ]
  run "$RUNNER" --tests-dir --execute
  [ "$status" -ne 0 ]
  [[ "$output" == *'missing value for --tests-dir'* ]] || return 1
  run "$RUNNER" --unknown
  [ "$status" -ne 0 ]
  [ ! -e "$CALL_LOG" ]
}

@test "suite explicitly authorizes its shard child" {
  cat > "${BATS_TEST_TMPDIR}/shard-probe" <<'PROBE'
#!/bin/bash
printf '%s\n' "$@"
PROBE
  chmod +x "${BATS_TEST_TMPDIR}/shard-probe"
  run env RUN_BATS_SHARDS="${BATS_TEST_TMPDIR}/shard-probe" \
    "${REPO_ROOT}/scripts/run-bats-suite.sh" --execute --shards 2 --tests-dir "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$output" = $'--execute\n--shards\n2\n--tests-dir\n'"$FIXTURE" ]
}

@test "shards run every real fixture test exactly once and propagate failure" {
  export FIXTURE_RUNS="${BATS_TEST_TMPDIR}/executed"
  cat > "${FIXTURE}/kubernetes/kind/tests/example.bats" <<'TESTS'
TEST_MARKER "first fixture" {
  printf 'first\n' >> "$FIXTURE_RUNS"
}
TEST_MARKER "second fixture" {
  printf 'second\n' >> "$FIXTURE_RUNS"
  false
}
TESTS
  sed 's/^TEST_MARKER/@test/' "${FIXTURE}/kubernetes/kind/tests/example.bats" > "${BATS_TEST_TMPDIR}/fixture.bats"
  mv "${BATS_TEST_TMPDIR}/fixture.bats" "${FIXTURE}/kubernetes/kind/tests/example.bats"
  run env BATS="$(command -v bats)" BATS_PROGRESS_SECONDS=0 "$RUNNER" --execute --shards 2 --tests-dir "${FIXTURE}/kubernetes/kind/tests"
  [ "$status" -ne 0 ]
  [ "$(sort "$FIXTURE_RUNS")" = $'first\nsecond' ]
  [[ "$output" == *'not ok shard'* ]] || return 1
  sed '/^  false$/d' "${FIXTURE}/kubernetes/kind/tests/example.bats" > "${BATS_TEST_TMPDIR}/passing.bats"
  mv "${BATS_TEST_TMPDIR}/passing.bats" "${FIXTURE}/kubernetes/kind/tests/example.bats"
  : > "$FIXTURE_RUNS"
  run env BATS="$(command -v bats)" BATS_PROGRESS_SECONDS=0 "$RUNNER" --execute --shards 2 --tests-dir "${FIXTURE}/kubernetes/kind/tests"
  [ "$status" -eq 0 ]
  [ "$(sort "$FIXTURE_RUNS")" = $'first\nsecond' ]
}
