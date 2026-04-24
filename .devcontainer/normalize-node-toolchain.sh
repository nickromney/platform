#!/usr/bin/env bash
set -euo pipefail

NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"

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
