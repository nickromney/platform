#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

export VARIANT_LABEL="${VARIANT_LABEL:-Lima}"
export CONTAINER_NAME="${CONTAINER_NAME:-limavm-platform-gateway-443}"
export IMAGE_TAG="${IMAGE_TAG:-platform/lima-gateway-proxy:dev}"
export UPSTREAM_PORT="${UPSTREAM_PORT:-30070}"

exec "${REPO_ROOT}/kubernetes/scripts/host-gateway-proxy.sh" "$@"
