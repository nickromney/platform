#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=kubernetes/scripts/docker-local-registry-lib.sh
source "${REPO_ROOT}/kubernetes/scripts/docker-local-registry-lib.sh"
IMAGE_LIST_FILE="${IMAGE_LIST_FILE:-${REPO_ROOT}/kubernetes/lima/preload-images.txt}"
CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
OPTIONAL="${OPTIONAL:-0}"
PRELOAD_IMAGES_SCRIPT="${PRELOAD_IMAGES_SCRIPT:-${REPO_ROOT}/terraform/kubernetes/scripts/preload-images.sh}"

warn() { echo "WARN $*" >&2; }

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Mirrors required Lima preload images into the local Docker registry cache.

$(shell_cli_standard_options)
EOF
}

skip_or_fail() {
  if [ "${OPTIONAL}" = "1" ]; then
    warn "$1"
    exit 0
  fi

  echo "sync-local-image-cache: $1" >&2
  exit 1
}

shell_cli_handle_standard_no_args usage "would sync Lima preload images from ${IMAGE_LIST_FILE} into ${CACHE_PUSH_HOST}" "$@"

command -v curl >/dev/null 2>&1 || skip_or_fail "curl not found"
registry_require_tools

[ -f "${IMAGE_LIST_FILE}" ] || skip_or_fail "image list not found: ${IMAGE_LIST_FILE}"
[ -f "${PRELOAD_IMAGES_SCRIPT}" ] || skip_or_fail "preload helper not found: ${PRELOAD_IMAGES_SCRIPT}"
registry_assert_reachable "${CACHE_PUSH_HOST}" || skip_or_fail "local cache not reachable at http://${CACHE_PUSH_HOST}/v2/"

if [ -z "${DOCKER_CONFIG:-}" ]; then
  docker_config_dir="$(mktemp -d)"
  mkdir -p "${docker_config_dir}"
  printf '{}\n' > "${docker_config_dir}/config.json"
  export DOCKER_CONFIG="${docker_config_dir}"
  trap 'rm -rf "${docker_config_dir}"' EXIT
fi

mirror_remote_image() {
  local source_ref="$1"
  local repo=""
  local tag=""
  local cache_ref=""

  IFS=$'\t' read -r repo tag < <(registry_cache_repo_and_tag "${source_ref}")
  cache_ref="${CACHE_PUSH_HOST}/${repo}:${tag}"

  if registry_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${tag}"; then
    echo "OK   cached ${cache_ref}"
    return 0
  fi

  if ! docker image inspect "${source_ref}" >/dev/null 2>&1; then
    if ! docker pull "${source_ref}" >/dev/null 2>&1; then
      warn "could not pull ${source_ref}"
      return 0
    fi
  fi

  echo "SYNC ${source_ref} -> ${cache_ref}"
  if ! docker tag "${source_ref}" "${cache_ref}"; then
    warn "could not tag ${source_ref} as ${cache_ref}"
    return 0
  fi
  if ! docker push "${cache_ref}" >/dev/null 2>&1; then
    warn "could not push ${cache_ref}"
  fi
}

image_stream() {
  "${PRELOAD_IMAGES_SCRIPT}" --execute --print-images --image-list "${IMAGE_LIST_FILE}"
}

while IFS= read -r image; do
  [[ -z "${image}" || "${image}" =~ ^# ]] && continue
  mirror_remote_image "${image}"
done < <(image_stream)
