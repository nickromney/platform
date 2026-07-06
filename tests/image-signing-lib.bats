#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export IMAGE_SIGNING_KEY_DIR="${BATS_TEST_TMPDIR}/signing"
  mkdir -p "${TEST_BIN}"
}

write_fake_cosign() {
  cat > "${TEST_BIN}/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${COSIGN_LOG}"
case "$1" in
  generate-key-pair)
    prefix=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --output-key-prefix)
          shift
          prefix="$1"
          ;;
      esac
      shift
    done
    printf '%s\n' "PRIVATE" > "${prefix}.key"
    printf '%s\n' "PUBLIC" > "${prefix}.pub"
    ;;
  sign)
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/cosign"
}

@test "image signing helper is inert when disabled" {
  export ENABLE_IMAGE_SIGNING=false
  export COSIGN_LOG="${BATS_TEST_TMPDIR}/cosign.log"

  run bash -c "source '${REPO_ROOT}/kubernetes/scripts/image-signing-lib.sh'; image_signing_ensure_keypair; image_signing_sign_ref '127.0.0.1:5002/platform/demo:latest'"

  [ "${status}" -eq 0 ]
  [ ! -e "${IMAGE_SIGNING_KEY_DIR}/local-platform-cosign.key" ]
  [ ! -e "${COSIGN_LOG}" ]
}

@test "image signing helper generates a keypair and signs refs when enabled" {
  write_fake_cosign
  export PATH="${TEST_BIN}:/usr/bin:/bin"
  export COSIGN_LOG="${BATS_TEST_TMPDIR}/cosign.log"
  export ENABLE_IMAGE_SIGNING=true

  run bash -c "source '${REPO_ROOT}/kubernetes/scripts/image-signing-lib.sh'; image_signing_ensure_keypair; image_signing_sign_ref '127.0.0.1:5002/platform/demo:latest'"

  [ "${status}" -eq 0 ]
  [ -f "${IMAGE_SIGNING_KEY_DIR}/local-platform-cosign.key" ]
  [ -f "${IMAGE_SIGNING_KEY_DIR}/local-platform-cosign.pub" ]

  run cat "${COSIGN_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"generate-key-pair --output-key-prefix ${IMAGE_SIGNING_KEY_DIR}/local-platform-cosign"* ]]
  [[ "${output}" == *"sign --yes --allow-insecure-registry --key ${IMAGE_SIGNING_KEY_DIR}/local-platform-cosign.key 127.0.0.1:5002/platform/demo:latest"* ]]
}
