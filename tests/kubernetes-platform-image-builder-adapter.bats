#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

assert_shared_platform_image_builder() {
  local variant="$1"
  local target="$2"
  local output=""

  run make -n -C "${REPO_ROOT}/kubernetes/${variant}" "${target}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'CACHE_PUSH_HOST='* ]]
  [[ "${output}" == *'kubernetes/scripts/build-local-platform-images.sh" --execute'* ]]
  [[ "${output}" != *'kubernetes/kind/scripts/build-local-platform-images.sh'* ]]
}

@test "kind build-local-platform-images calls the shared platform image builder" {
  assert_shared_platform_image_builder "kind" "build-local-platform-images"
}

@test "lima build-local-platform-images calls the shared platform image builder" {
  assert_shared_platform_image_builder "lima" "build-local-platform-images"
}

@test "shared platform image builder sources shared cache helpers" {
  script="${REPO_ROOT}/kubernetes/scripts/build-local-platform-images.sh"

  run grep -F 'kubernetes/kind/scripts/local-cache-lib.sh' "${script}"
  [ "${status}" -ne 0 ]

  run grep -F 'kubernetes/scripts/local-cache-lib.sh' "${script}"
  [ "${status}" -eq 0 ]
}
