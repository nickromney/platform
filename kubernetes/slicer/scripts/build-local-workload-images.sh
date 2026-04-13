#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=kubernetes/scripts/docker-local-registry-lib.sh
source "${SCRIPT_DIR}/../../scripts/docker-local-registry-lib.sh"
CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-platform}"
TAG="${TAG:-latest}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
SENTIMENT_MODEL_ID="${SENTIMENT_MODEL_ID:-}"

usage() {
  cat <<EOF
Usage: build-local-workload-images.sh [--dry-run] [--execute]

Builds and pushes workload images into the local registry cache for Slicer-based
workflows.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would build and push Slicer workload images into ${CACHE_PUSH_HOST} with tag ${TAG}" "$@"

command -v curl >/dev/null 2>&1 || { echo "build-local-workload-images: curl not found" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "build-local-workload-images: docker not found" >&2; exit 1; }

curl -fsS "http://${CACHE_PUSH_HOST}/v2/" >/dev/null 2>&1 || {
  echo "build-local-workload-images: local cache not reachable at http://${CACHE_PUSH_HOST}/v2/" >&2
  exit 1
}

commit_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"

docker_build() {
  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --load --provenance=false "$@"
    return
  fi

  DOCKER_BUILDKIT=1 docker build "$@"
}

tag_exists_in_cache() {
  local repo="$1"
  local tag="$2"
  local payload

  payload="$(curl -fsS "http://${CACHE_PUSH_HOST}/v2/${repo}/tags/list" 2>/dev/null || true)"
  [[ -n "${payload}" ]] && printf '%s' "${payload}" | grep -F "\"${tag}\"" >/dev/null 2>&1
}

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
    && tag_exists_in_cache "${repo}" "${commit_tag}" \
    && tag_exists_in_cache "${repo}" "${TAG}"; then
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
  docker_build "${cmd[@]}"

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
  "${REPO_ROOT}/apps/sentiment/api-sentiment/Dockerfile" \
  --build-arg "SENTIMENT_MODEL_ID=${SENTIMENT_MODEL_ID}"

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
