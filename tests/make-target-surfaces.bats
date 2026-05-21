#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "repo-owned Makefiles load every explicit phony target" {
  run "${REPO_ROOT}/scripts/check-make-target-surfaces.sh" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"repo-owned Makefiles"* ]]
}
