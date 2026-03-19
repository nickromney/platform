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
  [[ "${output}" == *"make 900 check-security"* ]]
  [[ "${output}" == *"Docker-only hosts       -> use ../kind"* ]]
}

@test "slicer stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 apply AUTO_APPROVE=1"* ]]
  [[ "${output}" == *"make 100 check-security"* ]]
}

@test "slicer typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}

@test "slicer supports stage-first check-security syntax" {
  run make -n -C "${REPO_ROOT}/kubernetes/slicer" 900 check-security

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "slicer stage 100 plan explains the daemon requirement" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100 plan

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"require a reachable Slicer daemon"* ]]
}
