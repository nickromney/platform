#!/usr/bin/env bash
set -euo pipefail

BASE_DOMAIN="${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
CHATGPT_URL="https://chatgpt.dev.${BASE_DOMAIN}"
MCP_URL="https://mcpserver.dev.${BASE_DOMAIN}/mcp"
LLM_URL="https://llm.${BASE_DOMAIN}/v1/chat/completions"

usage() {
  cat <<EOF
Usage: $(basename "$0") [json|env|urls]

Print the local agentgateway MCP wiring for chatgpt-sim.
EOF
}

mode="${1:-json}"
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
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
