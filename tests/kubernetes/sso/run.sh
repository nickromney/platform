#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INSTALL_HINTS="${REPO_ROOT}/scripts/install-tool-hints.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
DEFAULT_STAGE_TFVARS="${REPO_ROOT}/kubernetes/kind/stages/900-sso.tfvars"
ENSURE_PLAYWRIGHT_BROWSERS="${ENSURE_PLAYWRIGHT_BROWSERS:-${REPO_ROOT}/kubernetes/scripts/ensure-playwright-browsers.sh}"
STAGE_TFVARS="${STAGE_TFVARS:-}"
STAGE_TFVARS_FILES="${STAGE_TFVARS_FILES:-}"
SSO_E2E_SKIP_PLAYWRIGHT_INSTALL="${SSO_E2E_SKIP_PLAYWRIGHT_INSTALL:-0}"
PLATFORM_PLAYWRIGHT_MODE="${PLATFORM_PLAYWRIGHT_MODE:-native}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Runs the Kubernetes SSO Playwright end-to-end test suite with stage-derived
feature toggles.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would run the Kubernetes SSO end-to-end test suite" "$@"

if [ -z "${STAGE_TFVARS}" ] && [ -f "${DEFAULT_STAGE_TFVARS}" ]; then
  STAGE_TFVARS="${DEFAULT_STAGE_TFVARS}"
fi

tfvar_files=()
if [ -n "${STAGE_TFVARS_FILES}" ]; then
  IFS=':' read -r -a tfvar_files <<<"${STAGE_TFVARS_FILES}"
elif [ -n "${STAGE_TFVARS}" ]; then
  tfvar_files=("${STAGE_TFVARS}")
fi

tfvar_value() {
  local key="$1"
  local default_value="$2"

  local existing_files=()
  local file=""
  for file in "${tfvar_files[@]}"; do
    if [ -n "${file}" ] && [ -f "${file}" ]; then
      existing_files+=("${file}")
    fi
  done

  if [ "${#existing_files[@]}" -eq 0 ]; then
    echo "${default_value}"
    return 0
  fi

  local value
  value="$(
    sed -nE \
      -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
      -e "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^\"#[:space:]]+).*/\\1/p" \
      "${existing_files[@]}" | tail -n 1
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
    "${INSTALL_HINTS}" --execute --plain "${tool}" | sed 's/^/  /' >&2
  fi
  exit 1
}

require_tool node
require_tool bun

cd "${SCRIPT_DIR}"

decode_base64() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

playwright_core_version() {
  node -p "require('./node_modules/playwright-core/package.json').version"
}

docker_host_internal_ip() {
  local image="$1"

  # ahostsv4 forces the A record: with --add-host host-gateway Docker writes
  # both families to /etc/hosts with IPv6 first, and Chromium resolver rules
  # pointing at the IPv6 ULA do not route through the Desktop host gateway.
  docker run --rm --add-host host.docker.internal:host-gateway "${image}" \
    sh -lc "getent ahostsv4 host.docker.internal | awk 'NR==1 { print \$1 }'"
}

devcontainer_host_resolver_rules() {
  local devcontainer_host_ip=""

  devcontainer_host_ip="$(getent hosts host.docker.internal 2>/dev/null | awk 'NR==1 { print $1 }')"
  if [ -n "${devcontainer_host_ip}" ]; then
    printf 'MAP *.127.0.0.1.sslip.io %s,MAP 127.0.0.1.sslip.io %s\n' "${devcontainer_host_ip}" "${devcontainer_host_ip}"
  fi
}

docker_host_resolver_rules() {
  local image="$1"
  local host_ip=""

  host_ip="$(docker_host_internal_ip "${image}")"
  if [ -z "${host_ip}" ]; then
    echo "Failed to resolve host.docker.internal inside ${image}" >&2
    exit 1
  fi
  printf 'MAP *.127.0.0.1.sslip.io %s,MAP 127.0.0.1.sslip.io %s\n' "${host_ip}" "${host_ip}"
}

mkcert_root_ca() {
  local caroot=""

  command -v mkcert >/dev/null 2>&1 || return 0
  caroot="$(mkcert -CAROOT 2>/dev/null || true)"
  if [ -n "${caroot}" ] && [ -f "${caroot}/rootCA.pem" ]; then
    printf '%s\n' "${caroot}/rootCA.pem"
  fi
}

ensure_playwright_docker_image() {
  local image="$1"

  require_tool docker
  if docker image inspect "${image}" >/dev/null 2>&1; then
    return 0
  fi
  docker pull "${image}"
}

run_playwright_in_docker() {
  local playwright_version="$1"
  local host_resolver_rules="$2"
  shift 2
  local test_args=("$@")
  local image="mcr.microsoft.com/playwright:v${playwright_version}-noble"
  local root_ca=""
  local docker_args=()
  local env_name=""

  ensure_playwright_docker_image "${image}"
  root_ca="$(mkcert_root_ca)"

  if [ -z "${host_resolver_rules}" ]; then
    host_resolver_rules="$(docker_host_resolver_rules "${image}")"
  fi

  docker_args=(
    run --rm
    --add-host host.docker.internal:host-gateway
    -v "${REPO_ROOT}:/workspace"
    -w /workspace/tests/kubernetes/sso
  )

  # The specs also read credential/config env families beyond SSO_E2E_*
  # (see tests/*.spec.ts): pass each family through by prefix.
  for env_prefix in SSO_E2E_ OIDC_ KEYCLOAK_ DEX_ PLATFORM_DEMO_ PW_SLOWMO; do
    while IFS= read -r env_name; do
      [ -n "${env_name}" ] || continue
      docker_args+=(-e "${env_name}")
    done < <(compgen -e "${env_prefix}" || true)
  done

  docker_args+=(
    -e "SSO_E2E_ENABLE_SIGNOZ=${SSO_E2E_ENABLE_SIGNOZ}"
    -e "SSO_E2E_ENABLE_HEADLAMP=${SSO_E2E_ENABLE_HEADLAMP}"
    -e "SSO_E2E_ENABLE_VICTORIA_LOGS=${SSO_E2E_ENABLE_VICTORIA_LOGS}"
    -e "SSO_E2E_ENABLE_BACKSTAGE=${SSO_E2E_ENABLE_BACKSTAGE}"
    -e "SSO_E2E_ENABLE_MCP=${SSO_E2E_ENABLE_MCP}"
    -e "SSO_E2E_ENABLE_SENTIMENT=${SSO_E2E_ENABLE_SENTIMENT}"
    -e "SSO_E2E_ENABLE_SUBNETCALC=${SSO_E2E_ENABLE_SUBNETCALC}"
    -e "SSO_E2E_PROVIDER=${SSO_E2E_PROVIDER_VALUE}"
    -e "SSO_E2E_KEYCLOAK_REALM=${SSO_E2E_KEYCLOAK_REALM_VALUE}"
    -e "SSO_E2E_BASE_PORT=${SSO_E2E_BASE_PORT_VALUE}"
    -e "SSO_E2E_HOST_RESOLVER_RULES=${host_resolver_rules}"
    -e "SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET=${SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET_VALUE}"
    -e "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1"
  )

  if [ -n "${root_ca}" ]; then
    docker_args+=(
      -v "${root_ca}:/certs/mkcert-rootCA.pem:ro"
      -e "NODE_EXTRA_CA_CERTS=/certs/mkcert-rootCA.pem"
    )
  fi

  docker_args+=("${image}" npx playwright test)
  if [ "${HEADED:-0}" = "1" ]; then
    docker_args+=(--headed)
  fi
  # bash 3.2 + set -u treats empty-array expansion as unbound; guard it.
  docker_args+=(${test_args[@]+"${test_args[@]}"})

  docker "${docker_args[@]}"
}

SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ:-$(tfvar_bool enable_signoz false)}"
SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP:-$(tfvar_bool enable_headlamp false)}"
SSO_E2E_ENABLE_VICTORIA_LOGS="${SSO_E2E_ENABLE_VICTORIA_LOGS:-$(tfvar_bool enable_victoria_logs false)}"
SSO_E2E_ENABLE_BACKSTAGE="${SSO_E2E_ENABLE_BACKSTAGE:-$(tfvar_bool enable_backstage true)}"
SSO_E2E_ENABLE_MCP="${SSO_E2E_ENABLE_MCP:-true}"
SSO_E2E_ENABLE_SENTIMENT="${SSO_E2E_ENABLE_SENTIMENT:-$(tfvar_bool enable_app_repo_sentiment true)}"
SSO_E2E_ENABLE_SUBNETCALC="${SSO_E2E_ENABLE_SUBNETCALC:-$(tfvar_bool enable_app_repo_subnetcalc true)}"
SSO_E2E_PROVIDER_VALUE="${SSO_E2E_PROVIDER:-$(tfvar_value sso_provider keycloak)}"
SSO_E2E_KEYCLOAK_REALM_VALUE="${SSO_E2E_KEYCLOAK_REALM:-$(tfvar_value keycloak_realm platform)}"
SSO_E2E_BASE_PORT_VALUE="${SSO_E2E_BASE_PORT:-$(tfvar_value gateway_https_host_port 443)}"
SSO_E2E_HOST_RESOLVER_RULES_VALUE="${SSO_E2E_HOST_RESOLVER_RULES:-}"
SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET_VALUE="${SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET:-}"
SSO_E2E_TEST_GREP_VALUE="${SSO_E2E_TEST_GREP:-}"
if [ "${SSO_E2E_BASE_PORT_VALUE}" = "443" ]; then
  SSO_E2E_BASE_PORT_VALUE=""
fi

if [ -z "${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" ] && [ "${PLATFORM_DEVCONTAINER:-0}" = "1" ]; then
  SSO_E2E_HOST_RESOLVER_RULES_VALUE="$(devcontainer_host_resolver_rules)"
fi

if [ -z "${SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET_VALUE}" ] \
  && [ "${SSO_E2E_ENABLE_MCP}" = "true" ] \
  && [ "${SSO_E2E_PROVIDER_VALUE}" = "keycloak" ] \
  && command -v kubectl >/dev/null 2>&1; then
  kubectl_args=()
  if [ -n "${KUBECONFIG_CONTEXT:-}" ]; then
    kubectl_args+=(--context "${KUBECONFIG_CONTEXT}")
  fi
  encoded_secret="$(kubectl "${kubectl_args[@]}" get secret -n sso oauth2-proxy-oidc -o jsonpath='{.data.client-secret}' 2>/dev/null || true)"
  if [ -n "${encoded_secret}" ]; then
    SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET_VALUE="$(printf '%s' "${encoded_secret}" | decode_base64)"
  fi
fi

bun install --frozen-lockfile
test_args=()
if [ -n "${SSO_E2E_TEST_GREP_VALUE}" ]; then
  test_args+=(--grep "${SSO_E2E_TEST_GREP_VALUE}")
fi

case "${PLATFORM_PLAYWRIGHT_MODE}" in
  native)
    if [ "${SSO_E2E_SKIP_PLAYWRIGHT_INSTALL}" = "1" ]; then
      echo "Skipping Playwright browser install because SSO_E2E_SKIP_PLAYWRIGHT_INSTALL=1"
    else
      "${ENSURE_PLAYWRIGHT_BROWSERS}" --execute
    fi
    ;;
  docker)
    run_playwright_in_docker "$(playwright_core_version)" "${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" ${test_args[@]+"${test_args[@]}"}
    exit 0
    ;;
  *)
    echo "PLATFORM_PLAYWRIGHT_MODE must be native or docker, got: ${PLATFORM_PLAYWRIGHT_MODE}" >&2
    exit 1
    ;;
esac

if [ "${HEADED:-0}" = "1" ]; then
  SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ}" \
  SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP}" \
  SSO_E2E_ENABLE_VICTORIA_LOGS="${SSO_E2E_ENABLE_VICTORIA_LOGS}" \
  SSO_E2E_ENABLE_BACKSTAGE="${SSO_E2E_ENABLE_BACKSTAGE}" \
  SSO_E2E_ENABLE_MCP="${SSO_E2E_ENABLE_MCP}" \
  SSO_E2E_ENABLE_SENTIMENT="${SSO_E2E_ENABLE_SENTIMENT}" \
  SSO_E2E_ENABLE_SUBNETCALC="${SSO_E2E_ENABLE_SUBNETCALC}" \
  SSO_E2E_PROVIDER="${SSO_E2E_PROVIDER_VALUE}" \
  SSO_E2E_KEYCLOAK_REALM="${SSO_E2E_KEYCLOAK_REALM_VALUE}" \
  SSO_E2E_BASE_PORT="${SSO_E2E_BASE_PORT_VALUE}" \
  SSO_E2E_HOST_RESOLVER_RULES="${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" \
  SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET="${SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET_VALUE}" \
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
  bun run test:headed -- ${test_args[@]+"${test_args[@]}"}
else
  SSO_E2E_ENABLE_SIGNOZ="${SSO_E2E_ENABLE_SIGNOZ}" \
  SSO_E2E_ENABLE_HEADLAMP="${SSO_E2E_ENABLE_HEADLAMP}" \
  SSO_E2E_ENABLE_VICTORIA_LOGS="${SSO_E2E_ENABLE_VICTORIA_LOGS}" \
  SSO_E2E_ENABLE_BACKSTAGE="${SSO_E2E_ENABLE_BACKSTAGE}" \
  SSO_E2E_ENABLE_MCP="${SSO_E2E_ENABLE_MCP}" \
  SSO_E2E_ENABLE_SENTIMENT="${SSO_E2E_ENABLE_SENTIMENT}" \
  SSO_E2E_ENABLE_SUBNETCALC="${SSO_E2E_ENABLE_SUBNETCALC}" \
  SSO_E2E_PROVIDER="${SSO_E2E_PROVIDER_VALUE}" \
  SSO_E2E_KEYCLOAK_REALM="${SSO_E2E_KEYCLOAK_REALM_VALUE}" \
  SSO_E2E_BASE_PORT="${SSO_E2E_BASE_PORT_VALUE}" \
  SSO_E2E_HOST_RESOLVER_RULES="${SSO_E2E_HOST_RESOLVER_RULES_VALUE}" \
  SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET="${SSO_E2E_OAUTH2_PROXY_CLIENT_SECRET_VALUE}" \
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
  bun run test -- ${test_args[@]+"${test_args[@]}"}
fi
