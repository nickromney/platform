#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "apps make help exposes the Trivy security workflow" {
  run make -C "${REPO_ROOT}/apps" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"prereqs"* ]]
  [[ "${output}" == *"test"* ]]
  [[ "${output}" == *"trivy-prereqs"* ]]
  [[ "${output}" == *"trivy-scan"* ]]
  [[ "${output}" == *"trivy-scan-images"* ]]
  [[ "${output}" == *"trivy-scan-gitea"* ]]
}

@test "apps test delegates to the compose smoke workflow" {
  run make -n -C "${REPO_ROOT}/apps" test

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"compose-smoke"* ]]
  [[ "${output}" == *"./sentiment/tests/compose-smoke.sh"* ]]
  [[ "${output}" == *"./subnet-calculator/tests/compose-smoke.sh"* ]]
}
