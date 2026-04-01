#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/local-cache-lib.sh"

CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
CACHE_BUILD_HOST="${CACHE_BUILD_HOST:-${CACHE_PUSH_HOST}}"
BASE_IMAGE_NAMESPACE="${BASE_IMAGE_NAMESPACE:-platform-cache}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-platform}"
TAG="${TAG:-latest}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-12.3.1}"
GRAFANA_BASE_IMAGE_SOURCE="${GRAFANA_BASE_IMAGE_SOURCE:-docker.io/grafana/grafana:${GRAFANA_IMAGE_TAG}}"
PLUGIN_FETCH_IMAGE_SOURCE="${PLUGIN_FETCH_IMAGE_SOURCE:-docker.io/library/alpine:3.22}"
VICTORIA_LOGS_PLUGIN_VERSION="${VICTORIA_LOGS_PLUGIN_VERSION:-0.26.3}"
VICTORIA_LOGS_PLUGIN_URL="${VICTORIA_LOGS_PLUGIN_URL:-https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/v${VICTORIA_LOGS_PLUGIN_VERSION}/victoriametrics-logs-datasource-v${VICTORIA_LOGS_PLUGIN_VERSION}.zip}"

require_local_cache_tools
assert_local_cache_reachable "${CACHE_PUSH_HOST}"

commit_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"

build_and_push() {
  local image_name="$1"
  local build_context="$2"
  local dockerfile_path="$3"
  local version_tag="$4"
  shift 4

  local repo="${IMAGE_NAMESPACE}/${image_name}"
  local latest_ref="${CACHE_PUSH_HOST}/${repo}:${TAG}"
  local version_ref="${CACHE_PUSH_HOST}/${repo}:${version_tag}"
  local commit_ref=""
  local cmd=()

  if [ -n "${commit_tag}" ]; then
    commit_ref="${CACHE_PUSH_HOST}/${repo}:${commit_tag}"
  fi

  if [ "${FORCE_REBUILD}" != "1" ] \
    && tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${version_tag}" \
    && tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${TAG}" \
    && { [ -z "${commit_tag}" ] || tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${commit_tag}"; }; then
    echo "OK   cached ${version_ref}"
    return 0
  fi

  echo "BUILD ${image_name}"
  cmd=(-t "${version_ref}" -f "${dockerfile_path}")
  while [[ $# -gt 0 ]]; do
    cmd+=("$1")
    shift
  done
  cmd+=("${build_context}")
  docker_build_local "${cmd[@]}"

  docker tag "${version_ref}" "${latest_ref}"
  docker_push_local_registry "${version_ref}"
  docker_push_local_registry "${latest_ref}"

  if [ -n "${commit_ref}" ]; then
    docker tag "${version_ref}" "${commit_ref}"
    docker_push_local_registry "${commit_ref}"
  fi

  echo "PUSH  ${version_ref}"
}

grafana_version_tag="${GRAFANA_IMAGE_TAG}-v${VICTORIA_LOGS_PLUGIN_VERSION}"
grafana_base_repo="${BASE_IMAGE_NAMESPACE}/grafana-grafana"
plugin_fetch_repo="${BASE_IMAGE_NAMESPACE}/library-alpine"
grafana_base_ref="${CACHE_BUILD_HOST}/${grafana_base_repo}:${GRAFANA_IMAGE_TAG}"
plugin_fetch_ref="${CACHE_BUILD_HOST}/${plugin_fetch_repo}:3.22"

mirror_image_into_cache \
  "${GRAFANA_BASE_IMAGE_SOURCE}" \
  "${CACHE_PUSH_HOST}" \
  "${grafana_base_repo}" \
  "${GRAFANA_IMAGE_TAG}" \
  "${FORCE_REBUILD}"

mirror_image_into_cache \
  "${PLUGIN_FETCH_IMAGE_SOURCE}" \
  "${CACHE_PUSH_HOST}" \
  "${plugin_fetch_repo}" \
  "3.22" \
  "${FORCE_REBUILD}"

build_and_push \
  "grafana-victorialogs" \
  "${REPO_ROOT}" \
  "${REPO_ROOT}/kubernetes/kind/images/grafana-victorialogs/Dockerfile" \
  "${grafana_version_tag}" \
  --build-arg GRAFANA_BASE_IMAGE="${grafana_base_ref}" \
  --build-arg PLUGIN_FETCH_IMAGE="${plugin_fetch_ref}" \
  --build-arg GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG}" \
  --build-arg VICTORIA_LOGS_PLUGIN_URL="${VICTORIA_LOGS_PLUGIN_URL}"
