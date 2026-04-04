#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_FILE="${SCRIPT_DIR}/compose-platform.pem"
KEY_FILE="${SCRIPT_DIR}/compose-platform-key.pem"

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert is required but was not found in PATH." >&2
  exit 1
fi

CAROOT="$(mkcert -CAROOT 2>/dev/null || true)"
if [[ -z "${CAROOT}" || ! -f "${CAROOT}/rootCA.pem" || ! -f "${CAROOT}/rootCA-key.pem" ]]; then
  echo "mkcert is installed but its local CA is not ready." >&2
  echo "Run 'mkcert -install' and try again." >&2
  exit 1
fi

mkdir -p "${SCRIPT_DIR}"

mkcert \
  -cert-file "${CERT_FILE}" \
  -key-file "${KEY_FILE}" \
  dex.compose.127.0.0.1.sslip.io \
  subnetcalc.dev.compose.127.0.0.1.sslip.io \
  subnetcalc.uat.compose.127.0.0.1.sslip.io

chmod 600 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"

echo "Generated compose TLS certs:"
echo "  cert -> ${CERT_FILE}"
echo "  key  -> ${KEY_FILE}"
