#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "apps make help exposes the Trivy security workflow" {
  run make -C "${REPO_ROOT}/apps" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"trivy-prereqs"* ]]
  [[ "${output}" == *"trivy-scan"* ]]
  [[ "${output}" == *"trivy-scan-images"* ]]
  [[ "${output}" == *"trivy-scan-gitea"* ]]
}
