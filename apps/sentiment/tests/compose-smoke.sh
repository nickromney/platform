#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERRIDE_FILE="${SCRIPT_DIR}/compose.smoke.override.yml"
REPO_ROOT="$(cd "${APP_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: compose-smoke.sh [--dry-run] [--execute]

Run the lightweight sentiment compose smoke test against the local stack.

$(shell_cli_standard_options)
EOF
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "${APP_DIR}/compose.yml" -f "${OVERRIDE_FILE}" "$@"
    return
  fi

  if command -v podman-compose >/dev/null 2>&1; then
    podman-compose -f "${APP_DIR}/compose.yml" -f "${OVERRIDE_FILE}" "$@"
    return
  fi

  echo "compose-smoke: docker compose or podman-compose is required" >&2
  exit 1
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

wait_for_sentiment_post() {
  local url="$1"

  for _ in $(seq 1 90); do
    local body
    if body="$(curl -fsS -X POST "${url}" -H 'Content-Type: application/json' -d '{"text":"I love how small and fast this is."}' 2>/dev/null)"; then
      if [[ "${body}" == *'"label":"positive"'* || "${body}" == *'"label":"neutral"'* || "${body}" == *'"label":"negative"'* ]]; then
        printf '%s\n' "${body}"
        return 0
      fi
    fi
    sleep 2
  done

  echo "compose-smoke: timed out waiting for sentiment POST (${url})" >&2
  return 1
}

cleanup() {
  compose_cmd down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

shell_cli_handle_standard_no_args usage "would run the sentiment compose smoke workflow" "$@"

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build --no-deps sentiment-api sentiment-auth-frontend edge

wait_for_url "http://localhost:8305/" "sentiment edge frontend"
wait_for_url "http://localhost:8305/api/v1/health" "sentiment edge API"

curl -fsS "http://localhost:8305/" | grep -q "<title>Sentiment (Authenticated)</title>"
curl -fsS "http://localhost:8305/api/v1/health" | grep -q '"status":"ok"'
wait_for_sentiment_post "http://localhost:8305/api/v1/comments" | grep -Eq '"label":"(positive|neutral|negative)"'

echo "compose smoke passed for sentiment"
