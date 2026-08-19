#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "lima sync-image-cache calls the shared image sync adapter directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" sync-image-cache STAGE=900

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'VARIANT_LABEL="Lima"'* ]]
  [[ "${output}" == *'IMAGE_LIST_FILE="'*"kubernetes/lima/preload-images.txt"* ]]
  [[ "${output}" == *'kubernetes/scripts/sync-local-image-cache.sh" --execute'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/sync-local-image-cache.sh'* ]]
}
