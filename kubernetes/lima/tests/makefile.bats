#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "lima help documents the stage-first workflow" {
  run make -C "${REPO_ROOT}/kubernetes/lima" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"make 900 check-security"* ]]
}

@test "lima stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/lima" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 plan"* ]]
  [[ "${output}" == *"make 100 check-security"* ]]
}

@test "lima typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/lima" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}

@test "lima supports stage-first check-security syntax" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" 900 check-security

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-security.sh"* ]]
}
