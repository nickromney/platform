#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
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
  grep -F 'sentiment-api                        = "host.docker.internal:5002/platform/sentiment-api:latest"' "${OUTPUT_FILE}"
}

@test "render-operator-overrides auto disables Backstage below the Docker memory floor" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "info" ]; then
  printf '%s\n' 8589934592
  exit 0
fi
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"

  run env \
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=registry \
    KIND_ENABLE_BACKSTAGE=auto \
    KIND_BACKSTAGE_MIN_DOCKER_MEMORY_BYTES=10737418240 \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'enable_backstage = false' "${OUTPUT_FILE}"
  grep -F 'Docker MemTotal=8589934592' "${OUTPUT_FILE}"
}

@test "render-operator-overrides auto enables Backstage at or above the Docker memory floor" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "info" ]; then
  printf '%s\n' 10737418240
  exit 0
fi
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/docker"

  run env \
    PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=registry \
    KIND_ENABLE_BACKSTAGE=auto \
    KIND_BACKSTAGE_MIN_DOCKER_MEMORY_BYTES=10737418240 \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'enable_backstage = true' "${OUTPUT_FILE}"
}

@test "render-operator-overrides accepts explicit Backstage on and off modes" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=load \
    KIND_ENABLE_BACKSTAGE=off \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'enable_backstage = false' "${OUTPUT_FILE}"

  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=load \
    KIND_ENABLE_BACKSTAGE=on \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  grep -F 'enable_backstage = true' "${OUTPUT_FILE}"
}

@test "render-operator-overrides requires a baked node image for baked mode" {
  run env \
    KIND_OPERATOR_OVERRIDES_FILE="${OUTPUT_FILE}" \
    KIND_IMAGE_DISTRIBUTION_MODE=baked \
    "${RENDER_SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"KIND_BAKED_NODE_IMAGE is required"* ]]
}
