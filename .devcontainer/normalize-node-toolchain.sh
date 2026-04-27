#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: normalize-node-toolchain.sh [--dry-run] [--execute]

Remove Corepack pnpm shims from the devcontainer Node install so Bun remains
the package-manager entrypoint for this repo.

$(shell_cli_standard_options)

Environment:
  NVM_DIR=/usr/local/share/nvm  Node feature nvm directory to normalize.
EOF
}

shell_cli_handle_standard_no_args usage "would remove Corepack pnpm shims from ${NVM_DIR}" "$@"

if [[ ! -d "${NVM_DIR}" ]]; then
  exit 0
fi

if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  . "${NVM_DIR}/nvm.sh"
  nvm use default >/dev/null 2>&1 || true
fi

shopt -s nullglob
rm -f \
  "${NVM_DIR}/current/bin/pnpm" \
  "${NVM_DIR}/current/bin/pnpx" \
  "${NVM_DIR}"/versions/node/*/bin/pnpm \
  "${NVM_DIR}"/versions/node/*/bin/pnpx
shopt -u nullglob

hash -r
