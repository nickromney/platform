#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"
DEFAULT_STAGE_TFVARS="${REPO_ROOT}/kubernetes/kind/stages/900-sso.tfvars"
STAGE_TFVARS="${STAGE_TFVARS:-}"

if [ -z "${STAGE_TFVARS}" ] && [ -f "${DEFAULT_STAGE_TFVARS}" ]; then
  STAGE_TFVARS="${DEFAULT_STAGE_TFVARS}"
fi

tfvar_value() {
  local key="$1"
  local default_value="$2"

  if [ -z "${STAGE_TFVARS}" ] || [ ! -f "${STAGE_TFVARS}" ]; then
    echo "${default_value}"
    return 0
  fi

  local value
  value="$(
    sed -nE \
      -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
      -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^\"#[:space:]]+).*/\\1/p" \
      "${STAGE_TFVARS}" | tail -n 1
  )"
  if [ -n "${value}" ]; then
    echo "${value}"
  else
    echo "${default_value}"
  fi
}

tfvar_bool() {
  tfvar_value "$1" "$2"
}

require_tool() {
  local tool="$1"

  if command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi

  echo "${tool} not found in PATH" >&2
  if [ -x "${INSTALL_HINTS}" ]; then
    echo "Install hints:" >&2
    "${INSTALL_HINTS}" --plain "${tool}" | sed 's/^/  /' >&2
  fi
  exit 1
}

warn_optional_tool() {
  local tool="$1"
  local reason="$2"

  if command -v "${tool}" >/dev/null 2>&1; then
    return 0
  fi

  echo "WARN ${tool} not found in PATH (${reason})" >&2
  if [ -x "${INSTALL_HINTS}" ]; then
    "${INSTALL_HINTS}" --plain "${tool}" | sed 's/^/  /' >&2
  fi
}

require_tool node
warn_optional_tool npx "useful for ad hoc Playwright CLI flows"
require_tool bun

cd "${SCRIPT_DIR}"

SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ:-$(tfvar_bool enable_signoz false)}"
SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP:-$(tfvar_bool enable_headlamp true)}"
SSO_E2E_ENABLE_VICTORIA_LOGS="${SSO_E2E_ENABLE_VICTORIA_LOGS:-$(tfvar_bool enable_victoria_logs false)}"
SSO_E2E_BASE_PORT_VALUE="${SSO_E2E_BASE_PORT:-$(tfvar_value gateway_https_host_port 443)}"
SSO_E2E_HOST_RESOLVER_RULES_VALUE="${SSO_E2E_HOST_RESOLVER_RULES:-}"
if [ "${SSO_E2E_BASE_PORT_VALUE}" = "443" ]; then
  SSO_E2E_BASE_PORT_VALUE=""
fi

if [ -z "${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" ] && [ "${PLATFORM_DEVCONTAINER:-0}" = "1" ]; then
  devcontainer_host_ip="$(getent hosts host.docker.internal 2>/dev/null | awk 'NR==1 { print $1 }')"
  if [ -n "${devcontainer_host_ip}" ]; then
    SSO_E2E_HOST_RESOLVER_RULES_VALUE="MAP *.127.0.0.1.sslip.io ${devcontainer_host_ip},MAP 127.0.0.1.sslip.io ${devcontainer_host_ip}"
  fi
fi

bun install --frozen-lockfile
bun x playwright install chromium

if [ "${HEADED:-0}" = "1" ]; then
  SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ}" \
  SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP}" \
  SSO_E2E_ENABLE_VICTORIA_LOGS="${SSO_E2E_ENABLE_VICTORIA_LOGS}" \
  SSO_E2E_BASE_PORT="${SSO_E2E_BASE_PORT_VALUE}" \
  SSO_E2E_HOST_RESOLVER_RULES="${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" \
  bun run test:headed
else
  SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ}" \
  SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP}" \
  SSO_E2E_ENABLE_VICTORIA_LOGS="${SSO_E2E_ENABLE_VICTORIA_LOGS}" \
  SSO_E2E_BASE_PORT="${SSO_E2E_BASE_PORT_VALUE}" \
  SSO_E2E_HOST_RESOLVER_RULES="${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" \
  bun run test
fi
