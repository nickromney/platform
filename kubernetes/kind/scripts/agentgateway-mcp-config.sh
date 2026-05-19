#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

BASE_DOMAIN="${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
CHATGPT_URL="https://chatgpt.dev.${BASE_DOMAIN}"
MCP_URL="https://mcpserver.dev.${BASE_DOMAIN}/mcp"
LLM_URL="https://llm.${BASE_DOMAIN}/v1/chat/completions"

usage() {
  cat <<EOF
$(shell_cli_usage_line " [--dry-run] [--execute] [json|env|urls]")

Print the local agentgateway MCP wiring for platform clients.

Modes:
  json  Print JSON wiring details (default)
  env   Print shell environment assignments
  urls  Print one URL per line

$(shell_cli_standard_options)
EOF
}

mode="json"
mode_set=0

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    json|env|urls)
      if [[ "${mode_set}" -eq 1 ]]; then
        shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
        exit 1
      fi
      mode="$1"
      mode_set=1
      shift
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would print local agentgateway MCP wiring in ${mode} format"

case "${mode}" in
  json)
    printf '{\n'
    printf '  "chatgpt_url": "%s",\n' "${CHATGPT_URL}"
    printf '  "mcp_url": "%s",\n' "${MCP_URL}"
    printf '  "llm_url": "%s",\n' "${LLM_URL}"
    printf '  "mcp_transport": "streamable-http",\n'
    printf '  "oauth_issuer": "https://keycloak.%s/realms/platform"\n' "${BASE_DOMAIN}"
    printf '}\n'
    ;;
  env)
    printf 'CHATGPT_URL=%q\n' "${CHATGPT_URL}"
    printf 'MCP_URL=%q\n' "${MCP_URL}"
    printf 'LLM_URL=%q\n' "${LLM_URL}"
    printf 'MCP_TRANSPORT=%q\n' "streamable-http"
    ;;
  urls)
    printf '%s\n%s\n%s\n' "${CHATGPT_URL}" "${MCP_URL}" "${LLM_URL}"
    ;;
esac
