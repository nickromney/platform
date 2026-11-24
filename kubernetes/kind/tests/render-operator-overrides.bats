#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export RENDER_SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/render-operator-overrides.sh"
  export OUTPUT_FILE="${BATS_TEST_TMPDIR}/operator-overrides.tfvars"
}

@test "render-operator-overrides writes the default load-mode worker count" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_WORKER_COUNT=1 \
    KIND_IMAGE_DISTRIBUTION_MODE=load \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_FILE}" ]
  grep -F 'worker_count = 1' "${OUTPUT_FILE}"
  ! grep -F 'enable_actions_runner = false' "${OUTPUT_FILE}"
  ! grep -F 'node_image =' "${OUTPUT_FILE}"
}

@test "render-operator-overrides writes registry mode workload shortcuts" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_WORKER_COUNT=2 \
    KIND_IMAGE_DISTRIBUTION_MODE=registry \
    KIND_LOCAL_IMAGE_CACHE_HOST=host.docker.internal:5002 \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'worker_count = 2' "${OUTPUT_FILE}"
  grep -F 'enable_image_preload = false' "${OUTPUT_FILE}"
  grep -F 'enable_actions_runner = false' "${OUTPUT_FILE}"
  grep -F 'enable_apps_dir_mount = false' "${OUTPUT_FILE}"
  grep -F 'enable_docker_socket_mount = false' "${OUTPUT_FILE}"
  grep -F 'prefer_external_workload_images = true' "${OUTPUT_FILE}"
  grep -E '"sentiment-api"[[:space:]]+= "host\.docker\.internal:5002/platform/sentiment-api:src-' "${OUTPUT_FILE}"
  grep -E '"platform-mcp"[[:space:]]+= "host\.docker\.internal:5002/platform/platform-mcp:' "${OUTPUT_FILE}"
}

@test "generated registry mode operator overrides match the image catalog" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=registry \
    KIND_LOCAL_IMAGE_CACHE_HOST=host.docker.internal:5002 \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]

  run "${REPO_ROOT}/kubernetes/workflow/validate-image-catalog-target-refs.sh" \
    --execute \
    --catalog "${REPO_ROOT}/kubernetes/workflow/image-catalog.json" \
    --target kind \
    --tfvars "${OUTPUT_FILE}" \
    --allow-source-tags

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated kind external image refs against image catalog"* ]]
}

@test "render-operator-overrides no longer writes a Backstage toggle" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=registry \
    KIND_ENABLE_BACKSTAGE=on \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  run grep -Fc 'backstage' "${OUTPUT_FILE}"
  [ "${output}" = "0" ]
}

@test "render-operator-overrides requires a baked node image for baked mode" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=baked \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"KIND_BAKED_NODE_IMAGE is required"* ]]
}

@test "render-operator-overrides leaves worker_count out when the operator did not pin one" {
  # This file is the last -var-file the kind stack passes, so a worker_count
  # written here outranks the resource profile. Emitting the old default of 1
  # unconditionally is what made a single-node profile impossible.
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=load \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_FILE}" ]
  ! grep -q 'worker_count' "${OUTPUT_FILE}"
}

@test "render-operator-overrides accepts a single-node worker count" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_WORKER_COUNT=0 \
    KIND_IMAGE_DISTRIBUTION_MODE=load \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'worker_count = 0' "${OUTPUT_FILE}"
}

@test "render-operator-overrides still rejects a non-numeric worker count" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_WORKER_COUNT=one \
    KIND_IMAGE_DISTRIBUTION_MODE=load \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"KIND_WORKER_COUNT must be a whole number"* ]]
}
