#!/usr/bin/env bash

IMAGE_SIGNING_ENABLED="${ENABLE_IMAGE_SIGNING:-false}"
IMAGE_SIGNING_KEY_DIR="${IMAGE_SIGNING_KEY_DIR:-${REPO_ROOT}/.run/image-signing}"
IMAGE_SIGNING_KEY_PREFIX="${IMAGE_SIGNING_KEY_PREFIX:-${IMAGE_SIGNING_KEY_DIR}/local-platform-cosign}"
IMAGE_SIGNING_PRIVATE_KEY="${IMAGE_SIGNING_PRIVATE_KEY:-${IMAGE_SIGNING_KEY_PREFIX}.key}"
IMAGE_SIGNING_PUBLIC_KEY="${IMAGE_SIGNING_PUBLIC_KEY:-${IMAGE_SIGNING_KEY_PREFIX}.pub}"

image_signing_is_enabled() {
  case "${IMAGE_SIGNING_ENABLED}" in
    true|TRUE|1|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

image_signing_require_tools() {
  command -v cosign >/dev/null 2>&1 || { echo "${0##*/}: cosign not found; install cosign or set ENABLE_IMAGE_SIGNING=false" >&2; exit 1; }
}

image_signing_ensure_keypair() {
  if ! image_signing_is_enabled; then
    return 0
  fi

  image_signing_require_tools
  mkdir -p "${IMAGE_SIGNING_KEY_DIR}"
  chmod 700 "${IMAGE_SIGNING_KEY_DIR}"

  if [ -f "${IMAGE_SIGNING_PRIVATE_KEY}" ] && [ -f "${IMAGE_SIGNING_PUBLIC_KEY}" ]; then
    return 0
  fi

  echo "KEYGEN cosign ${IMAGE_SIGNING_PUBLIC_KEY}"
  (
    umask 077
    COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" cosign generate-key-pair --output-key-prefix "${IMAGE_SIGNING_KEY_PREFIX}" >/dev/null
  )
}

image_signing_sign_ref() {
  local image_ref="$1"

  [ -n "${image_ref}" ] || return 0

  if ! image_signing_is_enabled; then
    return 0
  fi

  image_signing_ensure_keypair
  echo "SIGN  ${image_ref}"
  COSIGN_PASSWORD="${COSIGN_PASSWORD:-}" cosign sign --yes --allow-insecure-registry --key "${IMAGE_SIGNING_PRIVATE_KEY}" "${image_ref}" >/dev/null
}
