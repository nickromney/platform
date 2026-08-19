#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "kind build-local-workload-images calls the shared workload image builder directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" build-local-workload-images

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'VARIANT_LABEL="Kind"'* ]]
  [[ "${output}" == *'IMAGE_NAMESPACE="platform"'* ]]
  [[ "${output}" == *'TAG="latest"'* ]]
  [[ "${output}" == *'kubernetes/scripts/build-local-workload-images.sh" --execute'* ]]
  [[ "${output}" != *'kubernetes/kind/scripts/build-local-workload-images.sh'* ]]
}

@test "lima build-workload-images calls the shared workload image builder directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" build-workload-images

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'VARIANT_LABEL="Lima"'* ]]
  [[ "${output}" == *'IMAGE_NAMESPACE="platform"'* ]]
  [[ "${output}" == *'TAG="latest"'* ]]
  [[ "${output}" == *'kubernetes/scripts/build-local-workload-images.sh" --execute'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/build-local-workload-images.sh'* ]]
}
