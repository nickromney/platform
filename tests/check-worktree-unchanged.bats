#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/scripts/check-worktree-unchanged.sh"
  export FIXTURE="${BATS_TEST_TMPDIR}/repo"
  export SNAPSHOT="${BATS_TEST_TMPDIR}/snapshot"

  # Isolate the fixture from host git config entirely. Without this the fixture
  # inherits the operator's settings, and a repo that signs commits through an
  # agent (1Password, gpg-agent) fails here the moment that agent is locked --
  # a test that reads host state is not hermetic, and fails on one machine and
  # not another.
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null

  mkdir -p "${FIXTURE}"
  git -C "${FIXTURE}" init --quiet
  git -C "${FIXTURE}" config user.email test@example.com
  git -C "${FIXTURE}" config user.name Test
  git -C "${FIXTURE}" config commit.gpgsign false
  printf 'tracked\n' >"${FIXTURE}/tracked.txt"
  git -C "${FIXTURE}" add tracked.txt
  git -C "${FIXTURE}" commit --quiet -m "seed"
}

@test "verify passes when the test run changed nothing" {
  run bash -lc "cd '${FIXTURE}' && '${SCRIPT}' --execute --snapshot '${SNAPSHOT}' && '${SCRIPT}' --execute --verify '${SNAPSHOT}'"

  [ "${status}" -eq 0 ]
}

@test "verify fails when a stray untracked file appears" {
  # This is the cp regression: a test leaves a file behind and the suite is
  # still green, because nothing asserts the run was side-effect free.
  run bash -lc "cd '${FIXTURE}' && '${SCRIPT}' --execute --snapshot '${SNAPSHOT}' && : >cp && '${SCRIPT}' --execute --verify '${SNAPSHOT}'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"cp"* ]]
}

@test "verify fails when a tracked file is modified" {
  run bash -lc "cd '${FIXTURE}' && '${SCRIPT}' --execute --snapshot '${SNAPSHOT}' && printf 'changed\n' >>tracked.txt && '${SCRIPT}' --execute --verify '${SNAPSHOT}'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"tracked.txt"* ]]
}

@test "verify tolerates pre-existing dirt so long as the run adds none" {
  # A dirty working tree is normal mid-session. The guard asserts the suite
  # changed nothing, not that the tree was clean to begin with.
  run bash -lc "cd '${FIXTURE}' && : >already-dirty && '${SCRIPT}' --execute --snapshot '${SNAPSHOT}' && '${SCRIPT}' --execute --verify '${SNAPSHOT}'"

  [ "${status}" -eq 0 ]
}

@test "verify reports which paths the run introduced" {
  run bash -lc "cd '${FIXTURE}' && '${SCRIPT}' --execute --snapshot '${SNAPSHOT}' && : >stray-one && : >stray-two && '${SCRIPT}' --execute --verify '${SNAPSHOT}'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"stray-one"* ]]
  [[ "${output}" == *"stray-two"* ]]
}

@test "verify fails clearly when no snapshot was taken" {
  run bash -lc "cd '${FIXTURE}' && '${SCRIPT}' --execute --verify '${BATS_TEST_TMPDIR}/missing'"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"snapshot"* ]]
}
