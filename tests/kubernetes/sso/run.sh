#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEFAULT_STAGE_TFVARS="${REPO_ROOT}/kubernetes/kind/stages/900-sso.tfvars"
STAGE_TFVARS="${STAGE_TFVARS:-}"

if [ -z "${STAGE_TFVARS}" ] && [ -f "${DEFAULT_STAGE_TFVARS}" ]; then
  STAGE_TFVARS="${DEFAULT_STAGE_TFVARS}"
fi

tfvar_bool() {
  local key="$1"
  local default_value="$2"

  if [ -z "${STAGE_TFVARS}" ] || [ ! -f "${STAGE_TFVARS}" ]; then
    echo "${default_value}"
    return 0
  fi

  local value
  value="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(true|false).*/\\1/p" "${STAGE_TFVARS}" | tail -n 1)"
  if [ -n "${value}" ]; then
    echo "${value}"
  else
    echo "${default_value}"
  fi
}

command -v node >/dev/null 2>&1 || { echo "node not found in PATH"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm not found in PATH"; exit 1; }

cd "${SCRIPT_DIR}"

SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ:-$(tfvar_bool enable_signoz false)}"
SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP:-$(tfvar_bool enable_headlamp true)}"

npm ci
npx playwright install chromium

if [ "${HEADED:-0}" = "1" ]; then
  SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ}" \
  SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP}" \
  npm run test:headed
else
  SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ}" \
  SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP}" \
  npm test
fi
