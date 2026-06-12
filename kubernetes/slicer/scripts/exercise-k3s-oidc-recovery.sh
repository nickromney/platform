#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
SHARED_SCRIPT="${REPO_ROOT}/kubernetes/scripts/exercise-k3s-oidc-recovery.sh"
CONFIGURE_SCRIPT="${SLICER_OIDC_CONFIGURE_SCRIPT:-${SCRIPT_DIR}/configure-k3s-apiserver-oidc.sh}"

K3S_OIDC_RUNTIME="slicer" \
K3S_OIDC_CONFIGURE_SCRIPT="${CONFIGURE_SCRIPT}" \
"${SHARED_SCRIPT}" "$@"
