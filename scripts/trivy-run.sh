#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-${REPO_ROOT}/.run/trivy-cache}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/trivy-common.sh"

mkdir -p "${TRIVY_CACHE_DIR}"

local_status="$(trivy_local_status)"
case "${local_status}" in
  available:*)
    exec trivy --cache-dir "${TRIVY_CACHE_DIR}" "$@"
    ;;
  unparseable)
    printf 'trivy-run: local trivy is present but its version could not be determined\n' >&2
    ;;
  *)
    printf 'trivy-run: local trivy is not available; install it if you want to run app scans\n' >&2
    ;;
esac

exit 1
