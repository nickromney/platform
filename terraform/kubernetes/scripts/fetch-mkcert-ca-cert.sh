#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"

fail() { echo "fetch-mkcert-ca-cert: $*" >&2; exit 1; }
print_install_hint() {
  local tool="$1"
  if [ -x "${INSTALL_HINTS}" ]; then
    echo "Install hint:" >&2
    "${INSTALL_HINTS}" --plain "${tool}" >&2 || true
  fi
}

require_cmd() {
  local tool="$1"
  if command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi
  print_install_hint "${tool}"
  fail "${tool} not found"
}

require_cmd jq
require_cmd mkcert

CAROOT="$(mkcert -CAROOT 2>/dev/null || true)"
[[ -n "${CAROOT}" ]] || fail "mkcert -CAROOT returned empty"

CA_CERT="${CAROOT}/rootCA.pem"
[[ -f "${CA_CERT}" ]] || fail "mkcert CA cert not found at ${CA_CERT}"

ca_value="$(cat "${CA_CERT}")"
[[ -n "${ca_value}" ]] || fail "mkcert CA cert at ${CA_CERT} is empty"

jq -cn --arg value "${ca_value}" '{value: $value}'
