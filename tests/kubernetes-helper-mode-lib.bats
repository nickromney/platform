#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "helper_mode_enabled enables explicit on and disables explicit off" {
  run bash -c 'source "${REPO_ROOT}/kubernetes/scripts/helper-mode-lib.sh"; helper_mode_enabled on 700 100'
  [ "${status}" -eq 0 ]

  run bash -c 'source "${REPO_ROOT}/kubernetes/scripts/helper-mode-lib.sh"; helper_mode_enabled off 700 900'
  [ "${status}" -eq 1 ]
}

@test "helper_mode_enabled enables auto only at or above threshold" {
  run bash -c 'source "${REPO_ROOT}/kubernetes/scripts/helper-mode-lib.sh"; helper_mode_enabled auto 700 699'
  [ "${status}" -eq 1 ]

  run bash -c 'source "${REPO_ROOT}/kubernetes/scripts/helper-mode-lib.sh"; helper_mode_enabled auto 700 700'
  [ "${status}" -eq 0 ]
}

@test "helper_mode_enabled rejects invalid modes clearly" {
  run bash -c 'source "${REPO_ROOT}/kubernetes/scripts/helper-mode-lib.sh"; helper_mode_enabled maybe 700 700'
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Invalid helper mode: maybe"* ]]
}
