#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "lima check-kind-stopped target calls the shared checker directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-kind-stopped

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubernetes/scripts/check-kind-stopped.sh"'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/check-kind-stopped.sh'* ]]
}
