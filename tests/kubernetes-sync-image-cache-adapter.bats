#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "lima sync-image-cache calls the shared image sync adapter directly" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" sync-image-cache STAGE=900

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'VARIANT_LABEL="Lima"'* ]]
  [[ "${output}" == *'IMAGE_LIST_FILE="'*"kubernetes/lima/preload-images.txt"* ]]
  [[ "${output}" == *'kubernetes/scripts/sync-local-image-cache.sh" --execute'* ]]
  [[ "${output}" != *'kubernetes/lima/scripts/sync-local-image-cache.sh'* ]]
}
