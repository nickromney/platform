#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/preload-images.sh"
}

@test "preload-images blocks kind load with kind older than v0.32.0" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "version -q")
    printf 'v0.31.0\n'
    ;;
  *)
    printf 'unexpected kind command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/kind"
  printf 'busybox:latest\n' >"${image_list}"

  run env PATH="${stub_bin}:${PATH}" "${SCRIPT}" --execute --image-list "${image_list}" --cluster kind-local

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"kind load requires kind v0.32.0 or newer"* ]]
  [[ "${output}" == *"installed kind v0.31.0"* ]]
}

@test "preload-images allows kind load path with kind v0.32.0 or newer" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  local lock_file="${BATS_TEST_TMPDIR}/preload.lock"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "version -q")
    printf 'v0.32.0\n'
    ;;
  "get clusters")
    ;;
  *)
    printf 'unexpected kind command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/kind"

  cat >"${stub_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "image inspect busybox:latest")
    exit 0
    ;;
  *)
    printf 'unexpected docker command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/docker"
  printf 'busybox:latest\n' >"${image_list}"
  printf 'busybox:latest\t-\n' >"${lock_file}"

  run env PATH="${stub_bin}:${PATH}" "${SCRIPT}" --execute --image-list "${image_list}" --cluster kind-local --platform linux/amd64 --lock-file "${lock_file}" --parallelism 1

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Kind cluster 'kind-local' not found"* ]]
  [[ "${output}" != *"kind load requires kind v0.32.0 or newer"* ]]
}

@test "preload-images pull-only mode bypasses kind load version gate" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  local lock_file="${BATS_TEST_TMPDIR}/preload.lock"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/kind" <<'EOF'
#!/usr/bin/env bash
printf 'kind should not be invoked in pull-only mode: %s\n' "$*" >&2
exit 99
EOF
  chmod +x "${stub_bin}/kind"

  cat >"${stub_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "image inspect busybox:latest")
    exit 0
    ;;
  *)
    printf 'unexpected docker command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/docker"
  printf 'busybox:latest\n' >"${image_list}"
  printf 'busybox:latest\t-\n' >"${lock_file}"

  run env PATH="${stub_bin}:${PATH}" "${SCRIPT}" --execute --pull-only --image-list "${image_list}" --cluster kind-local --platform linux/amd64 --lock-file "${lock_file}" --parallelism 1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Done (pull-only mode)."* ]]
  [[ "${output}" != *"kind should not be invoked"* ]]
  [[ "${output}" != *"kind load requires kind v0.32.0 or newer"* ]]
}

@test "preload-images filters external-secrets image when disabled" {
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  cat >"${image_list}" <<'EOF'
ghcr.io/external-secrets/external-secrets:v2.7.0
busybox:latest
EOF

  run env PRELOAD_ENABLE_EXTERNAL_SECRETS=false "${SCRIPT}" --execute --print-images --image-list "${image_list}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"ghcr.io/external-secrets/external-secrets:v2.7.0"* ]]
  [[ "${output}" == *"busybox:latest"* ]]
}

@test "preload-images keeps external-secrets image when enabled" {
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  cat >"${image_list}" <<'EOF'
ghcr.io/external-secrets/external-secrets:v2.7.0
busybox:latest
EOF

  run env PRELOAD_ENABLE_EXTERNAL_SECRETS=true "${SCRIPT}" --execute --print-images --image-list "${image_list}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ghcr.io/external-secrets/external-secrets:v2.7.0"* ]]
  [[ "${output}" == *"busybox:latest"* ]]
}
