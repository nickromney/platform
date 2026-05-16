#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

export VARIANT_LABEL="${VARIANT_LABEL:-Lima}"

exec "${REPO_ROOT}/kubernetes/scripts/build-local-workload-images.sh" "$@"
