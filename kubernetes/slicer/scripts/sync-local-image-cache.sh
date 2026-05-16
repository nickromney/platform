#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

export VARIANT_LABEL="${VARIANT_LABEL:-Slicer}"
export IMAGE_LIST_FILE="${IMAGE_LIST_FILE:-${REPO_ROOT}/kubernetes/slicer/preload-images.txt}"

exec "${REPO_ROOT}/kubernetes/scripts/sync-local-image-cache.sh" "$@"
