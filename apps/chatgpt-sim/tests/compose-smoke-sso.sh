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

Run the ChatGPT Sim SSO compose smoke test.

$(shell_cli_standard_options)
EOF
}

compose_cmd() {
  compose_cli -f "${APP_DIR}/compose.yml" "$@"
}

url_status() {
  local url="$1"
  curl -k -sS -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true
}

wait_for_url_status() {
  local url="$1"
  local expected="$2"
  local label="$3"

  for _ in $(seq 1 90); do
    local status
    status="$(url_status "${url}")"
    if [ "${status}" = "${expected}" ]; then
      return 0
    fi
    sleep 2
  done

  echo "compose-smoke-sso: timed out waiting for ${label} (${url}) to return ${expected}" >&2
  return 1
}

wait_for_protected_url() {
  local url="$1"
  local label="$2"

  for _ in $(seq 1 90); do
    local status
    status="$(url_status "${url}")"
    case "${status}" in
      302|401|403)
        return 0
        ;;
      200)
        echo "compose-smoke-sso: ${label} was served directly instead of being protected" >&2
        return 1
        ;;
    esac
    sleep 2
  done

  echo "compose-smoke-sso: timed out waiting for protected ${label} (${url})" >&2
  return 1
}

cleanup() {
  compose_cmd --profile sso down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

shell_cli_handle_standard_no_args usage "would run the ChatGPT Sim SSO compose smoke test" "$@"

export PLATFORM_DEMO_PASSWORD="${PLATFORM_DEMO_PASSWORD:-local-dev-password}"
export OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-0123456789abcdef0123456789abcdef}"
export CHATGPT_SIM_PUBLIC_PORT=18084
export CHATGPT_SIM_APP_PORT=18085
export CHATGPT_SIM_KEYCLOAK_PORT=8500

(cd "${APP_DIR}/app" && make build-linux)

compose_cmd --profile sso down --remove-orphans >/dev/null 2>&1 || true
compose_cmd --profile sso up -d --build

wait_for_url_status "http://localhost:8500/realms/platform/.well-known/openid-configuration" "200" "Keycloak platform realm"
wait_for_protected_url "http://localhost:18084/" "frontend"
if curl -ksSIL "http://localhost:18084/" | grep -qi "invalid_scope"; then
  echo "compose-smoke-sso: oauth2-proxy login flow requested an invalid Keycloak scope" >&2
  exit 1
fi
curl -fsS "http://localhost:18084/app-shell.css" | grep -q ".header-actions"

echo "compose-smoke-sso: ChatGPT Sim Keycloak/oauth2-proxy stack passed"
