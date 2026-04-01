#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
IMAGE_LIST_FILE="${IMAGE_LIST_FILE:-${REPO_ROOT}/kubernetes/slicer/preload-images.txt}"
CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
OPTIONAL="${OPTIONAL:-0}"
PRELOAD_IMAGES_SCRIPT="${PRELOAD_IMAGES_SCRIPT:-${REPO_ROOT}/terraform/kubernetes/scripts/preload-images.sh}"

warn() { echo "WARN $*" >&2; }

usage() {
  cat <<EOF
Usage: sync-local-image-cache.sh [--dry-run] [--execute]

Mirrors required Slicer preload images into the local Docker registry cache.

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

shell_cli_handle_standard_no_args usage "would sync Slicer preload images from ${IMAGE_LIST_FILE} into ${CACHE_PUSH_HOST}" "$@"

command -v curl >/dev/null 2>&1 || skip_or_fail "curl not found"
command -v docker >/dev/null 2>&1 || skip_or_fail "docker not found"

[ -f "${IMAGE_LIST_FILE}" ] || skip_or_fail "image list not found: ${IMAGE_LIST_FILE}"
[ -f "${PRELOAD_IMAGES_SCRIPT}" ] || skip_or_fail "preload helper not found: ${PRELOAD_IMAGES_SCRIPT}"
curl -fsS "http://${CACHE_PUSH_HOST}/v2/" >/dev/null 2>&1 || skip_or_fail "local cache not reachable at http://${CACHE_PUSH_HOST}/v2/"

if [ -z "${DOCKER_CONFIG:-}" ]; then
  docker_config_dir="$(mktemp -d)"
  mkdir -p "${docker_config_dir}"
  printf '{}\n' > "${docker_config_dir}/config.json"
  export DOCKER_CONFIG="${docker_config_dir}"
  trap 'rm -rf "${docker_config_dir}"' EXIT
fi

tag_exists_in_cache() {
  local repo="$1"
  local tag="$2"
  local payload

  payload="$(curl -fsS "http://${CACHE_PUSH_HOST}/v2/${repo}/tags/list" 2>/dev/null || true)"
  [[ -n "${payload}" ]] && printf '%s' "${payload}" | grep -F "\"${tag}\"" >/dev/null 2>&1
}

cache_repo_and_tag() {
  local image_ref="$1"
  local ref_without_digest="${image_ref%%@*}"
  local ref_without_tag="${ref_without_digest}"
  local repo_path=""
  local tag="latest"
  local first_component=""

  if [[ "${ref_without_digest##*/}" == *:* ]]; then
    tag="${ref_without_digest##*:}"
    ref_without_tag="${ref_without_digest%:*}"
  fi

  if [[ "${ref_without_tag}" != */* ]]; then
    repo_path="library/${ref_without_tag}"
  else
    first_component="${ref_without_tag%%/*}"
    if [[ "${first_component}" == *.* || "${first_component}" == *:* || "${first_component}" == "localhost" ]]; then
      repo_path="${ref_without_tag#*/}"
    else
      repo_path="${ref_without_tag}"
    fi
  fi

  printf '%s\t%s\n' "${repo_path}" "${tag}"
}

mirror_remote_image() {
  local source_ref="$1"
  local repo=""
  local tag=""
  local cache_ref=""

  IFS=$'\t' read -r repo tag < <(cache_repo_and_tag "${source_ref}")
  cache_ref="${CACHE_PUSH_HOST}/${repo}:${tag}"

  if tag_exists_in_cache "${repo}" "${tag}"; then
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
  "${PRELOAD_IMAGES_SCRIPT}" --print-images --image-list "${IMAGE_LIST_FILE}"
}

while IFS= read -r image; do
  [[ -z "${image}" || "${image}" =~ ^# ]] && continue
  mirror_remote_image "${image}"
done < <(image_stream)
