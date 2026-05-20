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

Run the Platform MCP compose smoke test.

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

shell_cli_handle_standard_no_args usage "would run the Platform MCP compose smoke test" "$@"

(cd "${APP_DIR}/app" && make build-linux)

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build

wait_for_url "http://localhost:18085/health" "platform-mcp health"
curl -fsS "http://localhost:18085/health" | grep -q '"service":"platform-mcp"'
curl -fsS \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  "http://localhost:18085/mcp" \
  | grep -q '"platform-mcp"'

echo "compose-smoke: Platform MCP stack passed"
