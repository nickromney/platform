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
  [[ "${output}" == *"update"* ]]
  [[ "${output}" == *"trivy-prereqs"* ]]
  [[ "${output}" == *"trivy-scan"* ]]
  [[ "${output}" == *"trivy-scan-images"* ]]
  [[ "${output}" == *"trivy-scan-gitea"* ]]
}

@test "apps prereqs stays Trivy-optional" {
  run make -C "${REPO_ROOT}/apps" prereqs

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Trivy remains opt-in"* ]]
  [[ "${output}" != *"Runner mode:"* ]]
}

@test "apps test delegates to the compose smoke workflow" {
  run make -n -C "${REPO_ROOT}/apps" test

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"compose-smoke"* ]]
  [[ "${output}" == *"./sentiment/tests/compose-smoke.sh"* ]]
  [[ "${output}" == *"./subnet-calculator/tests/compose-smoke.sh"* ]]
}

@test "apps update delegates to each app root update workflow" {
  run make -n -C "${REPO_ROOT}/apps" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make --no-print-directory -C ./sentiment update"* ]]
  [[ "${output}" == *"make --no-print-directory -C ./subnet-calculator update"* ]]
}
