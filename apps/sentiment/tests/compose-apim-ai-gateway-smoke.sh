#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERRIDE_FILE="${SCRIPT_DIR}/compose.smoke.override.yml"
REPO_ROOT="$(cd "${APP_DIR}/../.." && pwd)"
APIM_AI_GATEWAY_BASE_URL="${APIM_AI_GATEWAY_BASE_URL:-http://127.0.0.1:8000}"
export PLATFORM_DEMO_PASSWORD="${PLATFORM_DEMO_PASSWORD:-local-dev-password}"
export OAUTH2_PROXY_COOKIE_SECRET="${OAUTH2_PROXY_COOKIE_SECRET:-0123456789abcdef0123456789abcdef}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/compose-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Run the sentiment smoke test with SENTIMENT_ANALYZER=apim-ai-gateway.
Requires the APIM simulator AI gateway stack to already be running.

$(shell_cli_standard_options)
EOF
}

compose_cmd() {
  compose_cli -f "${APP_DIR}/compose.yml" -f "${APP_DIR}/compose.apim-ai-gateway.yml" -f "${OVERRIDE_FILE}" "$@"
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

  echo "apim-ai-gateway-smoke: timed out waiting for ${label} (${url})" >&2
  return 1
}

wait_for_sentiment_post() {
  local url="$1"

  for _ in $(seq 1 60); do
    local body
    if body="$(curl -fsS -X POST "${url}" -H 'Content-Type: application/json' -d '{"text":"I love how small and fast this is."}' 2>/dev/null)"; then
      if [[ "${body}" == *'"label":"positive"'* || "${body}" == *'"label":"neutral"'* || "${body}" == *'"label":"negative"'* ]]; then
        printf '%s\n' "${body}"
        return 0
      fi
    fi
    sleep 2
  done

  echo "apim-ai-gateway-smoke: timed out waiting for sentiment POST (${url})" >&2
  return 1
}

cleanup() {
  compose_cmd down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

shell_cli_handle_standard_no_args usage "would run sentiment through the APIM simulator AI gateway" "$@"

wait_for_url "${APIM_AI_GATEWAY_BASE_URL}/apim/health" "APIM simulator health"

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build --no-deps sentiment-api sentiment-auth-frontend edge

wait_for_url "http://localhost:8305/api/v1/health" "sentiment edge API"
wait_for_sentiment_post "http://localhost:8305/api/v1/comments" | grep -Eq '"label":"(positive|neutral|negative)"'

echo "compose smoke passed for sentiment via APIM AI gateway"
