#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "adapter variants call the shared stage monotonicity checker directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-stage-monotonicity

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-stage-monotonicity.sh" --execute'* ]]
  [[ "${output}" == *'--stack-dir "'*"kubernetes/kind"* ]]
  [[ "${output}" == *'--label "kind"'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-stage-monotonicity

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-stage-monotonicity.sh" --execute'* ]]
  [[ "${output}" == *'--stack-dir "'*"kubernetes/lima"* ]]
  [[ "${output}" == *'--label "Lima"'* ]]
}
