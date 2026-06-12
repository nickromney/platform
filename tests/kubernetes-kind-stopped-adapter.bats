#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "lima and slicer check-kind-stopped targets call the shared checker directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-kind-stopped

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-kind-stopped.sh"'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/check-kind-stopped.sh'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/slicer" check-kind-stopped

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-kind-stopped.sh"'* ]]
  [[ "${output}" != *'kubernetes/slicer/scripts/check-kind-stopped.sh'* ]]
}
