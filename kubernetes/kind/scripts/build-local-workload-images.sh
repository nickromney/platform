#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/local-cache-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/workflow/image-build-lib.sh"

CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-platform}"
TAG="${TAG:-latest}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Builds and pushes workload images into the local registry cache for kind-based
workflows.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would build and push local workload images into ${CACHE_PUSH_HOST} with tag ${TAG}" "$@"

require_local_cache_tools
assert_local_cache_reachable "${CACHE_PUSH_HOST}"

IMAGE_BUILD_REQUIRE_COMMIT_TAG=1
IMAGE_BUILD_COMMIT_TAG="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"

image_build_catalog_build_loop workload workload
