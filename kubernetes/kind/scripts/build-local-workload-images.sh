#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=kubernetes/kind/scripts/local-cache-lib.sh
source "${SCRIPT_DIR}/local-cache-lib.sh"

CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-platform}"
TAG="${TAG:-latest}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

require_local_cache_tools
assert_local_cache_reachable "${CACHE_PUSH_HOST}"

commit_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"

build_and_push() {
  local image_name="$1"
  local build_context="$2"
  local dockerfile_path="$3"
  shift 3

  local repo="${IMAGE_NAMESPACE}/${image_name}"
  local latest_ref="${CACHE_PUSH_HOST}/${repo}:${TAG}"
  local commit_ref=""
  local cmd=()

  if [ -n "${commit_tag}" ]; then
    commit_ref="${CACHE_PUSH_HOST}/${repo}:${commit_tag}"
  fi

  if [ "${FORCE_REBUILD}" != "1" ] \
    && [ -n "${commit_tag}" ] \
    && tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${commit_tag}" \
    && tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${TAG}"; then
    echo "OK   cached ${commit_ref}"
    return 0
  fi

  echo "BUILD ${image_name}"
  cmd=(-t "${latest_ref}" -f "${dockerfile_path}")
  while [[ $# -gt 0 ]]; do
    cmd+=("$1")
    shift
  done
  cmd+=("${build_context}")
  docker_build_local "${cmd[@]}"

  if [ -n "${commit_ref}" ]; then
    docker tag "${latest_ref}" "${commit_ref}"
    docker_push_local_registry "${commit_ref}"
  fi

  docker_push_local_registry "${latest_ref}"
  echo "PUSH  ${latest_ref}"
}

build_and_push \
  "sentiment-api" \
  "${REPO_ROOT}/apps/sentiment/api-sentiment" \
  "${REPO_ROOT}/apps/sentiment/api-sentiment/Dockerfile"

build_and_push \
  "sentiment-auth-ui" \
  "${REPO_ROOT}/apps/sentiment/frontend-react-vite/sentiment-auth-ui" \
  "${REPO_ROOT}/apps/sentiment/frontend-react-vite/sentiment-auth-ui/Dockerfile"

build_and_push \
  "subnetcalc-api-fastapi-container-app" \
  "${REPO_ROOT}/apps/subnet-calculator/api-fastapi-container-app" \
  "${REPO_ROOT}/apps/subnet-calculator/api-fastapi-container-app/Dockerfile"

build_and_push \
  "subnetcalc-apim-simulator" \
  "${REPO_ROOT}/apps/subnet-calculator/apim-simulator" \
  "${REPO_ROOT}/apps/subnet-calculator/apim-simulator/Dockerfile"

build_and_push \
  "subnetcalc-frontend-typescript-vite" \
  "${REPO_ROOT}/apps/subnet-calculator" \
  "${REPO_ROOT}/apps/subnet-calculator/frontend-typescript-vite/Dockerfile"

build_and_push \
  "subnetcalc-frontend-react" \
  "${REPO_ROOT}/apps/subnet-calculator" \
  "${REPO_ROOT}/apps/subnet-calculator/frontend-react/Dockerfile" \
  --build-arg VITE_API_PROXY_ENABLED=true \
  --build-arg VITE_AUTH_METHOD=easyauth
