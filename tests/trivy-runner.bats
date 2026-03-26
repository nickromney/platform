#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export ORIGINAL_PATH="${PATH}"
  export TRIVY_CACHE_DIR="${TEST_TMPDIR}/trivy-cache"
  export PATH="${TEST_TMPDIR}/bin:${ORIGINAL_PATH}"
  mkdir -p "${TEST_TMPDIR}/bin"
}

teardown() {
  rm -rf "${TEST_TMPDIR}"
}

write_fake_trivy() {
  local version="$1"

  cat > "${TEST_TMPDIR}/bin/trivy" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${1:-}" == "--version" ]]; then
  printf 'Version: %s\n' "${version}"
  exit 0
fi

printf 'local:%s\n' "\$*"
EOF
  chmod +x "${TEST_TMPDIR}/bin/trivy"
}

write_fake_docker() {
  :
}

@test "trivy-run uses the local binary when it is available" {
  write_fake_trivy "0.70.0"

  run "${REPO_ROOT}/scripts/trivy-run.sh" fs apps/sentiment

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"local:--cache-dir ${TRIVY_CACHE_DIR} fs apps/sentiment"* ]]
}

@test "trivy-run fails cleanly when local trivy is missing" {
  run "${REPO_ROOT}/scripts/trivy-run.sh" fs apps/sentiment

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"local trivy is not available"* ]]
}

@test "trivy-scan-apps prereqs reports unavailable mode when local trivy is missing" {
  run "${REPO_ROOT}/scripts/trivy-scan-apps.sh" prereqs

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Runner mode: unavailable"* ]]
  [[ "${output}" == *"Scanning is optional."* ]]
}

@test "devcontainer assets do not install or reference trivy" {
  for file in \
    "${REPO_ROOT}/.devcontainer/Brewfile" \
    "${REPO_ROOT}/.devcontainer/install-toolchain.sh" \
    "${REPO_ROOT}/.devcontainer/Dockerfile"; do
    run grep -in "trivy" "${file}"
    [ "${status}" -eq 1 ]
  done
}
