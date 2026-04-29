#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"

NAMESPACE="${SIGNOZ_AUTH_PROXY_NAMESPACE:-observability}"
NAME="${SIGNOZ_AUTH_PROXY_SECRET_NAME:-signoz-auth-proxy-credentials}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Create/update the Signoz OIDC auth proxy secret.
$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would create or update the signoz-auth-proxy-credentials secret" \
  "$@"

: "${SIGNOZ_URL:?Set SIGNOZ_URL (e.g. http://signoz:8080)}"
: "${SIGNOZ_USER:?Set SIGNOZ_USER (e.g. signoz-admin@example.com)}"
: "${SIGNOZ_PASSWORD:?Set SIGNOZ_PASSWORD}"

kubectl -n "${NAMESPACE}" create secret generic "${NAME}" \
  --from-literal=SIGNOZ_URL="${SIGNOZ_URL}" \
  --from-literal=SIGNOZ_USER="${SIGNOZ_USER}" \
  --from-literal=SIGNOZ_PASSWORD="${SIGNOZ_PASSWORD}" \
  --dry-run=client -o yaml \
  | kubectl apply -f -
