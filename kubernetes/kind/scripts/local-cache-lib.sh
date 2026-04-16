#!/usr/bin/env bash

LOCAL_CACHE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${LOCAL_CACHE_LIB_DIR}/../../scripts/docker-local-registry-lib.sh"

require_local_cache_tools() {
  command -v curl >/dev/null 2>&1 || { echo "${0##*/}: curl not found" >&2; exit 1; }
  command -v docker >/dev/null 2>&1 || { echo "${0##*/}: docker not found" >&2; exit 1; }
}

assert_local_cache_reachable() {
  local cache_host="$1"

  curl -fsS "http://${cache_host}/v2/" >/dev/null 2>&1 || {
    echo "${0##*/}: local cache not reachable at http://${cache_host}/v2/" >&2
    exit 1
  }
}

docker_build_local() {
  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --load --provenance=false "$@"
    return
  fi

  DOCKER_BUILDKIT=1 docker build "$@"
}

ensure_local_image_tag() {
  local source_ref="$1"
  local target_ref="$2"

  if docker image inspect "${target_ref}" >/dev/null 2>&1; then
    return 0
  fi

  if ! docker image inspect "${source_ref}" >/dev/null 2>&1; then
    docker pull "${source_ref}" >/dev/null
  fi

  # BuildKit resolves FROM refs through the local image store first.
  # Restoring the exact cache tag here avoids a registry pull during builds.
  docker tag "${source_ref}" "${target_ref}"
}

tag_exists_in_cache() {
  local cache_host="$1"
  local repo="$2"
  local tag="$3"
  local payload

  payload="$(curl -fsS "http://${cache_host}/v2/${repo}/tags/list" 2>/dev/null || true)"
  [[ -n "${payload}" ]] && printf '%s' "${payload}" | grep -F "\"${tag}\"" >/dev/null 2>&1
}

mirror_image_into_cache() {
  local source_ref="$1"
  local cache_host="$2"
  local repo="$3"
  local tag="$4"
  local force_rebuild="${5:-0}"
  local target_ref="${cache_host}/${repo}:${tag}"

  if [ "${force_rebuild}" != "1" ] && tag_exists_in_cache "${cache_host}" "${repo}" "${tag}"; then
    ensure_local_image_tag "${source_ref}" "${target_ref}"
    echo "OK   cached ${target_ref}"
    return 0
  fi

  echo "MIRROR ${source_ref} -> ${target_ref}"
  docker pull "${source_ref}" >/dev/null
  docker tag "${source_ref}" "${target_ref}"
  docker_push_local_registry "${target_ref}"
  echo "PUSH  ${target_ref}"
}
