#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "k3s runtimes plan stage 800 local image helpers consistently" {
  run "${REPO_ROOT}/kubernetes/scripts/plan-local-image-helpers.sh" --execute \
    --stage 800 \
    --cache-mode auto \
    --platform-images-mode auto \
    --workload-images-mode auto \
    --prefer-external-platform-images true \
    --cache-available false \
    --runtime-image-cache-host host.local:5002 \
    --push-image-cache-url http://127.0.0.1:5002/v2/

  [ "${status}" -eq 0 ]
  [ "${output}" = $'ensure-image-cache\nsync-image-cache\nbuild-local-platform-images\nbuild-workload-images' ]
}

@test "planner fails clearly when stage needs cache but cache mode is off and unavailable" {
  run "${REPO_ROOT}/kubernetes/scripts/plan-local-image-helpers.sh" --execute \
    --stage 700 \
    --cache-mode off \
    --platform-images-mode auto \
    --workload-images-mode auto \
    --prefer-external-platform-images false \
    --cache-available false \
    --runtime-image-cache-host runtime.local:5002 \
    --push-image-cache-url http://127.0.0.1:5002/v2/

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Stage 700 expects workload images from runtime.local:5002"* ]]
  [[ "${output}" == *"Set PLATFORM_LOCAL_IMAGE_CACHE_MODE=on or start a compatible cache manually."* ]]
}

@test "planner emits skip messages for disabled image build helpers" {
  run "${REPO_ROOT}/kubernetes/scripts/plan-local-image-helpers.sh" --execute \
    --stage 800 \
    --cache-mode off \
    --platform-images-mode off \
    --workload-images-mode off \
    --prefer-external-platform-images true \
    --cache-available true \
    --runtime-image-cache-host runtime.local:5002 \
    --push-image-cache-url http://127.0.0.1:5002/v2/

  [ "${status}" -eq 0 ]
  [ "${output}" = $'message:Skipping platform image build (PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=off)\nmessage:Skipping workload image build (PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=off)' ]
}
