#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED_SCRIPT="$(cd "${SCRIPT_DIR}/../.." && pwd)/scripts/configure-k3s-apiserver-oidc.sh"

K3S_OIDC_RUNTIME="lima" \
K3S_OIDC_RUNTIME_LABEL="Lima" \
SHELL_CLI_SCRIPT_NAME_OVERRIDE="$(basename "$0")" \
exec "${SHARED_SCRIPT}" "$@"
