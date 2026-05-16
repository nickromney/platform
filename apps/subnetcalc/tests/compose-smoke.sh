#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/compose-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Run the lightweight subnetcalc compose smoke test against the local stack.

$(shell_cli_standard_options)
EOF
}

compose_cmd() {
  compose_cli -f "${APP_DIR}/compose.yml" "$@"
}

wait_for_url() {
  local url="$1"
  local label="$2"

  for _ in $(seq 1 60); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "compose-smoke: timed out waiting for ${label} (${url})" >&2
  return 1
}

cleanup() {
  compose_cmd down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

shell_cli_handle_standard_no_args usage "would run the subnetcalc compose smoke workflow" "$@"

export OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-dev-cookie-secret-32-bytes-minimum}"
export OAUTH2_PROXY_CLIENT_SECRET="${OAUTH2_PROXY_CLIENT_SECRET:-dev-oauth-secret}"
export STACK12_APIM_SUBSCRIPTION_KEY="${STACK12_APIM_SUBSCRIPTION_KEY:-dev-subscription-key}"
export STACK12_ADMIN_APIM_SUBSCRIPTION_KEY="${STACK12_ADMIN_APIM_SUBSCRIPTION_KEY:-dev-admin-subscription-key}"
if [ -z "${SUBNETCALC_LOCAL_PLATFORM:-}" ]; then
  case "$(uname -m)" in
    arm64|aarch64)
      export SUBNETCALC_LOCAL_PLATFORM=linux/arm64
      ;;
    *)
      export SUBNETCALC_LOCAL_PLATFORM=linux/amd64
      ;;
  esac
fi
case "${SUBNETCALC_LOCAL_PLATFORM}" in
  linux/arm64)
    export GOARCH=arm64
    ;;
  linux/amd64)
    export GOARCH=amd64
    ;;
  *)
    echo "compose-smoke: unsupported SUBNETCALC_LOCAL_PLATFORM=${SUBNETCALC_LOCAL_PLATFORM}" >&2
    exit 1
    ;;
esac

(cd "${APP_DIR}/app-go" && make build-linux)

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build subnetcalc-backend subnetcalc-frontend

wait_for_url "http://localhost:8090/api/v1/health" "Container App API"
wait_for_url "http://localhost:8003/" "Go frontend"

curl -fsS "http://localhost:8003/" | grep -q "IPv4 Subnet Calculator"
curl -fsS "http://localhost:8003/api/v1/health" | grep -q '"service":"Subnet Calculator API (Go)"'

echo "compose smoke passed for subnetcalc"
