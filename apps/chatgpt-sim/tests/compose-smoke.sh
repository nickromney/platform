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

Run the ChatGPT Sim compose smoke test.

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

shell_cli_handle_standard_no_args usage "would run the ChatGPT Sim compose smoke test" "$@"

(cd "${APP_DIR}/app" && make build-linux)

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build

wait_for_url "http://localhost:18084/health" "chatgpt-sim health"
wait_for_url "http://localhost:18084/" "chatgpt-sim frontend"

curl -fsS "http://localhost:18084/" | grep -q "<title>ChatGPT Sim</title>"
curl -fsS "http://localhost:18084/health" | grep -q '"dependency_footprint":"go-plus-shared-idpauth"'
curl -fsS "http://localhost:18084/health" | grep -q '"frontend_dependency_footprint":"vanilla"'
curl -fsS \
  -H "Content-Type: application/json" \
  -d '{"message":"who am I?","tool":"auto"}' \
  "http://localhost:18084/api/chat" \
  | grep -q '"selected_tool":"whoami"'

echo "compose-smoke: ChatGPT Sim stack passed"
