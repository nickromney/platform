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

Run the Platform MCP compose smoke test against the local server and Inspector.

$(shell_cli_standard_options)
EOF
}

compose_cmd() {
  compose_cli -f "${APP_DIR}/compose.yml" "$@"
}

wait_for_url() {
  local url="$1"
  local label="$2"

  for _ in $(seq 1 90); do
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

shell_cli_handle_standard_no_args usage "would run the Platform MCP compose smoke workflow" "$@"

http_port="${PLATFORM_MCP_COMPOSE_HTTP_PORT:-8089}"
metrics_port="${PLATFORM_MCP_COMPOSE_METRICS_PORT:-9099}"
inspector_port="${MCP_INSPECTOR_COMPOSE_UI_PORT:-6274}"

compose_cmd down --remove-orphans >/dev/null 2>&1 || true
compose_cmd up -d --build platform-mcp mcp-inspector

wait_for_url "http://localhost:${http_port}/health" "Platform MCP health"
wait_for_url "http://localhost:${metrics_port}/metrics" "Platform MCP metrics"
wait_for_url "http://localhost:${inspector_port}/" "MCP Inspector"

curl -fsS "http://localhost:${http_port}/health" | grep -q '"status":"ok"'
curl -fsS "http://localhost:${metrics_port}/metrics" | grep -q 'platform_mcp_tool_calls_total'

(
  cd "${APP_DIR}"
  PLATFORM_MCP_URL="http://localhost:${http_port}/mcp" uv run --extra dev python -m platform_mcp.smoke
) | grep -q '"d2_render"'

echo "compose smoke passed for platform-mcp"
