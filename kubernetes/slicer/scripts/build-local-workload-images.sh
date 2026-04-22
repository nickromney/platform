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
registry_require_tools
registry_assert_reachable "${CACHE_PUSH_HOST}"

commit_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"

docker_build() {
  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --load --provenance=false "$@"
    return
  fi

  DOCKER_BUILDKIT=1 docker build "$@"
}

build_and_push() {
  local image_name="$1"
  local build_context="$2"
  local dockerfile_path="$3"
  shift 3

  local repo="${IMAGE_NAMESPACE}/${image_name}"
  local build_ref="build-${image_name}:${TAG}"
  local latest_ref="${CACHE_PUSH_HOST}/${repo}:${TAG}"
  local commit_ref=""
  local cmd=()

  if [ -n "${commit_tag}" ]; then
    commit_ref="${CACHE_PUSH_HOST}/${repo}:${commit_tag}"
  fi

  if [ "${FORCE_REBUILD}" != "1" ] \
    && [ -n "${commit_tag}" ] \
    && registry_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${commit_tag}" \
    && registry_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${TAG}"; then
    echo "OK   cached ${commit_ref}"
    return 0
  fi

  echo "BUILD ${image_name}"
  # Build into a local staging tag first; the registry push is handled
  # explicitly after the image is loaded into the local daemon.
  cmd=(-t "${build_ref}" -f "${dockerfile_path}")
  while [[ $# -gt 0 ]]; do
    cmd+=("$1")
    shift
  done
  cmd+=("${build_context}")
  docker_build "${cmd[@]}"

  if [ -n "${commit_ref}" ]; then
    docker tag "${build_ref}" "${commit_ref}"
    docker_push_local_registry "${commit_ref}"
  fi

  docker tag "${build_ref}" "${latest_ref}"
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
  "${REPO_ROOT}/apps/subnetcalc/api-fastapi-container-app" \
  "${REPO_ROOT}/apps/subnetcalc/api-fastapi-container-app/Dockerfile"

build_and_push \
  "subnetcalc-apim-simulator" \
  "${REPO_ROOT}/apps/subnetcalc/apim-simulator" \
  "${REPO_ROOT}/apps/subnetcalc/apim-simulator/Dockerfile"

build_and_push \
  "subnetcalc-frontend-typescript-vite" \
  "${REPO_ROOT}/apps/subnetcalc" \
  "${REPO_ROOT}/apps/subnetcalc/frontend-typescript-vite/Dockerfile"
