#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
SECRET_NAME="${MKCERT_CA_SECRET_NAME:-mkcert-ca-key-pair}"

if ! command -v mkcert >/dev/null 2>&1; then
  cat >&2 <<'EOF'
mkcert not found; skipping mkcert CA bootstrap.

Install on macOS:
  brew install mkcert
  mkcert -install
EOF
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
