#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "slicer help documents the stage-first workflow" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
}

@test "slicer stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 apply AUTO_APPROVE=1"* ]]
}

@test "slicer typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}
