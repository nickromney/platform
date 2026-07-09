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

@test "preload-images refresh-lock preserves explicit digest refs without retagging digest targets" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local temp_root="${BATS_TEST_TMPDIR}/repo"
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  local lock_file="${BATS_TEST_TMPDIR}/preload.lock"
  local digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local image_ref="example.com/repo/app:v1@${digest}"
  mkdir -p "${stub_bin}" "${temp_root}/scripts/lib"
  ln -s "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${temp_root}/scripts/lib/shell-cli.sh"

  for rel in \
    apps/subnetcalc/app/Dockerfile \
    apps/apim-simulator/app/Dockerfile \
    apps/sentiment/app/Dockerfile \
    apps/chatgpt-sim/app/Dockerfile \
    apps/langfuse-demos/app/Dockerfile \
    apps/idp-core/app/Dockerfile \
    apps/platform-mcp/app/Dockerfile; do
    mkdir -p "${temp_root}/$(dirname "${rel}")"
    : >"${temp_root}/${rel}"
  done

  cat >"${stub_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "info -f {{.OSType}}")
    printf 'linux\n'
    ;;
  "info -f {{.Architecture}}")
    printf 'arm64\n'
    ;;
  image\ inspect*)
    exit 1
    ;;
  pull\ example.com/repo/app@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
    printf 'pulled digest\n'
    ;;
  tag*)
    printf 'unexpected docker tag for digest-pinned image: %s\n' "$*" >&2
    exit 2
    ;;
  buildx\ imagetools\ inspect*)
    printf 'unexpected digest resolution for explicit digest ref: %s\n' "$*" >&2
    exit 2
    ;;
  *)
    printf 'unexpected docker command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/docker"
  printf '%s\n' "${image_ref}" >"${image_list}"

  run env REPO_ROOT="${temp_root}" PATH="${stub_bin}:${PATH}" "${SCRIPT}" --execute --pull-only --image-list "${image_list}" --platform linux/arm64 --lock-file "${lock_file}" --refresh-lock --parallelism 1

  [ "${status}" -eq 0 ]
  [ "$(cat "${lock_file}")" = "$(printf '%s\texample.com/repo/app@%s\n' "${image_ref}" "${digest}")" ]
  [[ "${output}" == *"Done (pull-only mode)."* ]]
  [[ "${output}" != *"unexpected"* ]]
}

@test "preload-images kind load uses pinned digest ref when explicit digest image ref lacks a local tag" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local temp_root="${BATS_TEST_TMPDIR}/repo"
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  local lock_file="${BATS_TEST_TMPDIR}/preload.lock"
  local saved_ref_file="${BATS_TEST_TMPDIR}/saved-ref"
  local kind_load_called="${BATS_TEST_TMPDIR}/kind-load-called"
  local digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  local image_ref="example.com/repo/app:v1@${digest}"
  local pinned_ref="example.com/repo/app@${digest}"
  mkdir -p "${stub_bin}" "${temp_root}/scripts/lib"
  ln -s "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${temp_root}/scripts/lib/shell-cli.sh"

  for rel in \
    apps/subnetcalc/app/Dockerfile \
    apps/apim-simulator/app/Dockerfile \
    apps/sentiment/app/Dockerfile \
    apps/chatgpt-sim/app/Dockerfile \
    apps/langfuse-demos/app/Dockerfile \
    apps/idp-core/app/Dockerfile \
    apps/platform-mcp/app/Dockerfile; do
    mkdir -p "${temp_root}/$(dirname "${rel}")"
    : >"${temp_root}/${rel}"
  done

  cat >"${stub_bin}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "version -q")
    printf 'v0.32.0\n'
    ;;
  "get clusters")
    printf 'kind-local\n'
    ;;
  "get nodes --name kind-local")
    printf 'kind-local-control-plane\n'
    ;;
  load\ image-archive\ --name\ kind-local\ *)
    : >"${KIND_LOAD_CALLED:?}"
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

case "${1:-} ${2:-}" in
  "info -f")
    case "${3:-}" in
      "{{.OSType}}") printf 'linux\n' ;;
      "{{.Architecture}}") printf 'arm64\n' ;;
      *) printf 'unexpected docker info format: %s\n' "${3:-}" >&2; exit 2 ;;
    esac
    ;;
  "image inspect")
    case "${3:-}" in
      example.com/repo/app:v1@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
        exit 1
        ;;
      example.com/repo/app@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
        exit 0
        ;;
      *)
        printf 'unexpected docker image inspect ref: %s\n' "${3:-}" >&2
        exit 2
        ;;
    esac
    ;;
  "exec kind-local-control-plane")
    if [[ "${3:-}" == "ctr" && "${4:-}" == "--namespace=k8s.io" && "${5:-}" == "images" && "${6:-}" == "ls" && "${7:-}" == "-q" ]]; then
      exit 0
    fi
    printf 'unexpected docker exec command: %s\n' "$*" >&2
    exit 2
    ;;
  "save --platform")
    if [[ "${3:-}" != "linux/arm64" || "${4:-}" != "-o" ]]; then
      printf 'unexpected docker save platform command: %s\n' "$*" >&2
      exit 2
    fi
    printf '%s\n' "${6:-}" >"${DOCKER_SAVED_REF_FILE:?}"
    : >"${5:?}"
    ;;
  *)
    printf 'unexpected docker command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/docker"

  printf '%s\n' "${image_ref}" >"${image_list}"
  printf '%s\t%s\n' "${image_ref}" "${pinned_ref}" >"${lock_file}"

  run env REPO_ROOT="${temp_root}" PATH="${stub_bin}:${PATH}" DOCKER_SAVED_REF_FILE="${saved_ref_file}" KIND_LOAD_CALLED="${kind_load_called}" "${SCRIPT}" --execute --image-list "${image_list}" --cluster kind-local --platform linux/arm64 --lock-file "${lock_file}" --parallelism 1

  [ "${status}" -eq 0 ]
  [ "$(cat "${saved_ref_file}")" = "${pinned_ref}" ]
  [ -f "${kind_load_called}" ]
  [[ "${output}" == *"loaded  ${image_ref}"* ]]
  [[ "${output}" != *"skip    ${image_ref}"* ]]
  [[ "${output}" != *"unexpected"* ]]
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

@test "preload-images filters argo-rollouts controller by progressive delivery toggle" {
  local image_list="${BATS_TEST_TMPDIR}/images.txt"

  cat >"${image_list}" <<'EOF'
quay.io/argoproj/argo-rollouts:v1.9.0
busybox:latest
EOF

  run "${SCRIPT}" --execute --print-images --image-list "${image_list}" --tfvars "${REPO_ROOT}/kubernetes/kind/stages/100-cluster.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"quay.io/argoproj/argo-rollouts:v1.9.0"* ]]
  [[ "${output}" == *"busybox:latest"* ]]
}
