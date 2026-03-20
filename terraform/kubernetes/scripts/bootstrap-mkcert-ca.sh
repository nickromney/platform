#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
SECRET_NAME="${MKCERT_CA_SECRET_NAME:-mkcert-ca-key-pair}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"

print_install_hint() {
  local tool="$1"
  if [ -x "${INSTALL_HINTS}" ]; then
    echo "Install hint:" >&2
    "${INSTALL_HINTS}" --plain "${tool}" >&2 || true
  fi
}

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert not found; skipping mkcert CA bootstrap." >&2
  print_install_hint "mkcert"
  echo "After install, run: mkcert -install" >&2
  exit 0
fi

CAROOT="$(mkcert -CAROOT)"
CA_CERT="${CAROOT}/rootCA.pem"
CA_KEY="${CAROOT}/rootCA-key.pem"

if [[ ! -f "${CA_CERT}" || ! -f "${CA_KEY}" ]]; then
  echo "mkcert CA files not present under ${CAROOT}; run 'mkcert -install' then re-apply" >&2
  exit 0
fi

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Required namespace ${NAMESPACE} does not exist; Terraform should create it before mkcert bootstrap runs." >&2
  exit 1
fi

kubectl -n "${NAMESPACE}" create secret tls "${SECRET_NAME}" \
  --cert="${CA_CERT}" \
  --key="${CA_KEY}" \
  --dry-run=client -o yaml \
  | kubectl apply -f -

echo "Created/updated secret ${NAMESPACE}/${SECRET_NAME} from mkcert CA (CAROOT=${CAROOT})."
echo "Next: Argo cert-manager-config should reconcile and issue the platform-gateway TLS certificate."
