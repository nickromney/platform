#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${SIGNOZ_AUTH_PROXY_NAMESPACE:-observability}"
NAME="${SIGNOZ_AUTH_PROXY_SECRET_NAME:-signoz-auth-proxy-credentials}"

: "${SIGNOZ_URL:?Set SIGNOZ_URL (e.g. http://signoz:8080)}"
: "${SIGNOZ_USER:?Set SIGNOZ_USER (e.g. signoz-admin@example.com)}"
: "${SIGNOZ_PASSWORD:?Set SIGNOZ_PASSWORD}"

kubectl -n "${NAMESPACE}" create secret generic "${NAME}" \
  --from-literal=SIGNOZ_URL="${SIGNOZ_URL}" \
  --from-literal=SIGNOZ_USER="${SIGNOZ_USER}" \
  --from-literal=SIGNOZ_PASSWORD="${SIGNOZ_PASSWORD}" \
  --dry-run=client -o yaml \
  | kubectl apply -f -
