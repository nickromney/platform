#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "sync-gitea-policies: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Render the policies repository content for the current stack inputs and push it
to the configured Gitea repository.

$(shell_cli_standard_options)
EOF
}

# Allow the script to be sourced by tests and helper shells without immediately
# triggering the CLI preview/exit path.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  shell_cli_handle_standard_no_args usage "would render and sync the policies repository into Gitea" "$@"
fi

: "${STACK_DIR:?STACK_DIR is required}"
GITEA_SSH_USERNAME="${GITEA_SSH_USERNAME:-git}"
GITEA_REPO_OWNER="${GITEA_REPO_OWNER:-platform}"
GITEA_REPO_NAME="${GITEA_REPO_NAME:-policies}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/tf-defaults.sh"

require_gitea_runtime_env() {
  : "${GITEA_ADMIN_USERNAME:?GITEA_ADMIN_USERNAME is required}"
  : "${GITEA_ADMIN_PWD:?GITEA_ADMIN_PWD is required}"
  : "${GITEA_SSH_USERNAME:?GITEA_SSH_USERNAME is required (typically git)}"
  : "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"
  : "${GITEA_REPO_NAME:?GITEA_REPO_NAME is required}"
  : "${DEPLOY_KEY_TITLE:?DEPLOY_KEY_TITLE is required}"
  : "${DEPLOY_PUBLIC_KEY:?DEPLOY_PUBLIC_KEY is required}"
  : "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH is required}"
}

contract_value() {
  local key="$1"
  local file="${GITOPS_RENDER_CONTRACT_FILE:-}"

  if [[ -z "${file}" || ! -f "${file}" ]]; then
    return 0
  fi

  jq -er --arg key "${key}" 'if has($key) then .[$key] | tostring else empty end' "${file}" 2>/dev/null || true
}

contract_has_key() {
  local key="$1"
  local file="${GITOPS_RENDER_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || return 1
  jq -e --arg key "${key}" 'has($key)' "${file}" >/dev/null 2>&1
}

contract_default() {
  local env_name="$1"
  local contract_key="$2"
  local fallback="${3:-}"
  local value=""

  if contract_has_key "${contract_key}"; then
    value="$(contract_value "${contract_key}")"
    printf -v "${env_name}" '%s' "${value}"
    return 0
  fi

  local current=""
  eval "current=\"\${${env_name}:-}\""
  if [[ -n "${current}" ]]; then
    return 0
  fi

  value="${fallback}"
  printf -v "${env_name}" '%s' "${value}"
}

render_external_image_inputs() {
  cat <<'EOF'
workload|EXTERNAL_IMAGE_SENTIMENT_API|external_sentiment_api|sentiment-api|workload
workload|EXTERNAL_IMAGE_SENTIMENT_AUTH_UI|external_sentiment_ui|sentiment-auth-ui|workload
workload|EXTERNAL_IMAGE_SUBNETCALC_API|external_subnetcalc_api|subnetcalc-api|workload
workload|EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR|external_subnetcalc_apim|subnetcalc-apim-simulator|workload
workload|EXTERNAL_IMAGE_SUBNETCALC_FRONTEND|external_subnetcalc_frontend|subnetcalc-frontend|workload
platform|EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP|external_platform_mcp|platform-mcp|mcp
platform|EXTERNAL_PLATFORM_IMAGE_AUTH_CHAT|external_platform_auth_chat|auth-chat|auth-chat
platform|EXTERNAL_PLATFORM_IMAGE_CHATGPT_SIM|external_platform_chatgpt_sim|chatgpt-sim|chatgpt
platform|EXTERNAL_PLATFORM_IMAGE_LANGFUSE_DEMOS|external_platform_langfuse_demos|langfuse-demos|langfuse-demos
platform|EXTERNAL_PLATFORM_IMAGE_GRAFANA|external_platform_grafana|grafana-victorialogs|grafana
platform|EXTERNAL_PLATFORM_IMAGE_IDP_CORE|external_platform_idp_core|idp-core|idp
platform|EXTERNAL_PLATFORM_IMAGE_BACKSTAGE|external_platform_backstage|backstage|idp
EOF
}

load_external_image_contract_defaults() {
  local scope env_name contract_key image_name manifest_group

  while IFS='|' read -r scope env_name contract_key image_name manifest_group; do
    [[ -n "${scope}" && -n "${env_name}" && -n "${contract_key}" && -n "${image_name}" && -n "${manifest_group}" ]] || continue
    contract_default "${env_name}" "${contract_key}" ""
  done < <(render_external_image_inputs)
}

render_gitops_render_inputs() {
  cat <<'EOF'
string|GITEA_REPO_OWNER|repo_owner|$GITEA_REPO_OWNER
bool|GITEA_REPO_OWNER_IS_ORG|repo_is_org|false
bool|ENABLE_HUBBLE|enable_hubble|true
bool|ENABLE_POLICIES|enable_policies|true
bool|ENABLE_IMAGE_SIGNING|enable_image_signing|false
string|IMAGE_SIGNING_PUBLIC_KEY|image_signing_public_key|
bool|ENABLE_GATEWAY_TLS|enable_gateway_tls|true
string|GATEWAY_HTTPS_HOST_PORT|gateway_https_host_port|443
string|PLATFORM_BASE_DOMAIN|platform_base_domain|127.0.0.1.sslip.io
string|PLATFORM_ADMIN_BASE_DOMAIN|platform_admin_base_domain|$PLATFORM_BASE_DOMAIN
string|POLICIES_REPO_URL_CLUSTER|policies_repo_url_cluster|
string|ARGOCD_PUBLIC_HOST|argocd_public_host|
string|SSO_PUBLIC_URL|sso_public_url|
string|GITEA_PUBLIC_HOST|gitea_public_host|
string|GRAFANA_PUBLIC_HOST|grafana_public_host|
string|HEADLAMP_PUBLIC_HOST|headlamp_public_host|
string|HUBBLE_PUBLIC_HOST|hubble_public_host|
string|KYVERNO_PUBLIC_HOST|kyverno_public_host|
string|SENTIMENT_DEV_PUBLIC_HOST|sentiment_dev_public_host|
string|SENTIMENT_UAT_PUBLIC_HOST|sentiment_uat_public_host|
string|SUBNETCALC_DEV_PUBLIC_HOST|subnetcalc_dev_public_host|
string|SUBNETCALC_UAT_PUBLIC_HOST|subnetcalc_uat_public_host|
string|APIM_PUBLIC_HOST|apim_public_host|
string|ADMIN_ROUTE_ALLOWLIST_CIDRS|admin_route_allowlist_cidrs|
string|GATEWAY_TRUSTED_PROXY_CIDRS|gateway_trusted_proxy_cidrs|
bool|ENABLE_CERT_MANAGER|enable_cert_manager|true
bool|ENABLE_ACTIONS_RUNNER|enable_actions_runner|true
bool|ENABLE_APP_REPO_SENTIMENT|enable_app_repo_sentiment|false
bool|ENABLE_APP_REPO_SUBNETCALC|enable_app_repo_subnetcalc|false
bool|ENABLE_SUBNETCALC_APIM_GATEWAY|enable_subnetcalc_apim_gateway|true
bool|ENABLE_APIM_SIMULATOR|enable_apim_simulator|false
bool|ENABLE_AGENTGATEWAY_AI_GATEWAY|enable_agentgateway_ai_gateway|false
bool|ENABLE_PROMETHEUS|enable_prometheus|false
bool|ENABLE_ALERTMANAGER|enable_alertmanager|false
bool|ENABLE_GRAFANA|enable_grafana|false
bool|ENABLE_VICTORIA_LOGS|enable_victoria_logs|false
bool|ENABLE_OTEL_GATEWAY|enable_otel_gateway|false
bool|ENABLE_OBSERVABILITY_AGENT|enable_observability_agent|false
bool|ENABLE_METRICS_SERVER|enable_metrics_server|false
bool|ENABLE_EXTERNAL_SECRETS|enable_external_secrets|false
bool|ENABLE_PROGRESSIVE_DELIVERY|enable_progressive_delivery|false
bool|ENABLE_HEADLAMP|enable_headlamp|false
bool|ENABLE_SSO|enable_sso|false
bool|ENABLE_BACKSTAGE|enable_backstage|true
bool|HEADLAMP_CLUSTER_ROLE_BINDING_CREATE|headlamp_cluster_role_binding_create|true
bool|HEADLAMP_OIDC_SKIP_TLS_VERIFY|headlamp_oidc_skip_tls_verify|true
string|HEADLAMP_OIDC_CLIENT_SECRET|headlamp_oidc_client_secret|
bool|PREFER_EXTERNAL_WORKLOAD_IMAGES|prefer_external_images|false
string|MCP_PUBLIC_HOST|mcp_public_host|
string|MCP_CONSOLE_PUBLIC_HOST|mcp_console_public_host|
string|AGENTGATEWAY_AI_GATEWAY_PUBLIC_HOST|agentgateway_ai_gateway_public_host|
string|AGENTGATEWAY_AI_GATEWAY_MODEL|agentgateway_ai_gateway_model|
string|LANGFUSE_PUBLIC_HOST|langfuse_public_host|
string|LANGFUSE_TRACE_CHAT_PUBLIC_HOST|langfuse_trace_chat_public_host|
string|LANGFUSE_TOOL_AGENT_PUBLIC_HOST|langfuse_tool_agent_public_host|
string|LANGFUSE_EVAL_RUNNER_PUBLIC_HOST|langfuse_eval_runner_public_host|
bool|ENABLE_LANGFUSE|enable_langfuse|false
bool|ENABLE_LANGFUSE_DEMOS|enable_langfuse_demos|false
bool|PREFER_EXTERNAL_PLATFORM_IMAGES|prefer_external_platform|false
string|HARDENED_IMAGE_REGISTRY|hardened_image_registry|dhi.io
chart|AGENTGATEWAY_CHART_VERSION|agentgateway_chart_version|agentgateway_chart_version
chart|CERT_MANAGER_CHART_VERSION|cert_manager_chart_version|cert_manager_chart_version
chart|GRAFANA_CHART_VERSION|grafana_chart_version|grafana_chart_version
chart|HEADLAMP_CHART_VERSION|headlamp_chart_version|headlamp_chart_version
chart|METRICS_SERVER_CHART_VERSION|metrics_server_chart_version|metrics_server_chart_version
chart|EXTERNAL_SECRETS_CHART_VERSION|external_secrets_chart_version|external_secrets_chart_version
chart|KYVERNO_CHART_VERSION|kyverno_chart_version|kyverno_chart_version
chart|OAUTH2_PROXY_CHART_VERSION|oauth2_proxy_chart_version|oauth2_proxy_chart_version
chart|OPENTELEMETRY_COLLECTOR_CHART_VERSION|otel_chart_version|opentelemetry_collector_chart_version
chart|POLICY_REPORTER_CHART_VERSION|policy_reporter_chart_version|policy_reporter_chart_version
chart|PROMETHEUS_CHART_VERSION|prometheus_chart_version|prometheus_chart_version
chart|VICTORIA_LOGS_CHART_VERSION|victoria_logs_chart_version|victoria_logs_chart_version
tfvar|GRAFANA_IMAGE_REGISTRY|grafana_image_registry|grafana_image_registry
tfvar|GRAFANA_IMAGE_REPOSITORY|grafana_image_repository|grafana_image_repository
tfvar|GRAFANA_IMAGE_TAG|grafana_image_tag|grafana_image_tag
tfvar|GRAFANA_SIDECAR_IMAGE_REGISTRY|grafana_sidecar_image_registry|grafana_sidecar_image_registry
tfvar|GRAFANA_SIDECAR_IMAGE_REPOSITORY|grafana_sidecar_image_repository|grafana_sidecar_image_repository
tfvar|GRAFANA_SIDECAR_IMAGE_TAG|grafana_sidecar_image_tag|grafana_sidecar_image_tag
tfvar|GRAFANA_VICTORIA_LOGS_PLUGIN_URL|grafana_victoria_logs_plugin_url|grafana_victoria_logs_plugin_url
tfvar|GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS|grafana_liveness_initial_delay_seconds|grafana_liveness_initial_delay_seconds
EOF
}

gitops_render_input_fallback() {
  local input_type="$1"
  local fallback="$2"

  # The fallback values below are literal sentinels from render_input_spec.
  # shellcheck disable=SC2016
  case "${fallback}" in
    '$GITEA_REPO_OWNER')
      printf '%s\n' "${GITEA_REPO_OWNER}"
      ;;
    '$PLATFORM_BASE_DOMAIN')
      printf '%s\n' "${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
      ;;
    *)
      if [[ "${input_type}" == "chart" || "${input_type}" == "tfvar" ]]; then
        tf_default_from_variables "${fallback}"
      else
        printf '%s\n' "${fallback}"
      fi
      ;;
  esac
}

load_gitops_render_input_contract_defaults() {
  local input_type env_name contract_key fallback default_value

  while IFS='|' read -r input_type env_name contract_key fallback; do
    [[ -n "${input_type}" && -n "${env_name}" && -n "${contract_key}" ]] || continue
    default_value="$(gitops_render_input_fallback "${input_type}" "${fallback}")"
    contract_default "${env_name}" "${contract_key}" "${default_value}"
  done < <(render_gitops_render_inputs)
}

external_image_input_value() {
  local wanted_scope="$1"
  local wanted_image="$2"
  local scope env_name contract_key image_name manifest_group value

  while IFS='|' read -r scope env_name contract_key image_name manifest_group; do
    [[ "${scope}" == "${wanted_scope}" && "${image_name}" == "${wanted_image}" ]] || continue
    eval "value=\"\${${env_name}:-}\""
    printf '%s\n' "${value}"
    return 0
  done < <(render_external_image_inputs)

  printf '\n'
}

load_gitops_render_contract_defaults() {
  local file="${GITOPS_RENDER_CONTRACT_FILE:-}"

  if [[ -z "${file}" ]]; then
    return 0
  fi
  [[ -f "${file}" ]] || fail "GITOPS_RENDER_CONTRACT_FILE not found: ${file}"
  command -v jq >/dev/null 2>&1 || fail "jq not found"

  load_gitops_render_input_contract_defaults
  load_external_image_contract_defaults
}

load_gitops_render_contract_defaults

POLICIES_REPO_URL_CLUSTER="${POLICIES_REPO_URL_CLUSTER:-ssh://${GITEA_SSH_USERNAME}@gitea-ssh.gitea.svc.cluster.local:22/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git}"
GITEA_REPO_OWNER_IS_ORG="${GITEA_REPO_OWNER_IS_ORG:-false}"
GITEA_REPO_OWNER_FALLBACK="${GITEA_REPO_OWNER_FALLBACK:-}"
ENABLE_HUBBLE="${ENABLE_HUBBLE:-true}"
ENABLE_POLICIES="${ENABLE_POLICIES:-true}"
ENABLE_IMAGE_SIGNING="${ENABLE_IMAGE_SIGNING:-false}"
IMAGE_SIGNING_PUBLIC_KEY="${IMAGE_SIGNING_PUBLIC_KEY:-}"
ENABLE_GATEWAY_TLS="${ENABLE_GATEWAY_TLS:-true}"
GATEWAY_HTTPS_HOST_PORT="${GATEWAY_HTTPS_HOST_PORT:-443}"
PLATFORM_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_ADMIN_BASE_DOMAIN:-${PLATFORM_BASE_DOMAIN}}"
ARGOCD_PUBLIC_HOST="${ARGOCD_PUBLIC_HOST:-argocd.admin.${PLATFORM_BASE_DOMAIN}}"
GITEA_PUBLIC_HOST="${GITEA_PUBLIC_HOST:-gitea.admin.${PLATFORM_BASE_DOMAIN}}"
GRAFANA_PUBLIC_HOST="${GRAFANA_PUBLIC_HOST:-grafana.admin.${PLATFORM_BASE_DOMAIN}}"
HEADLAMP_PUBLIC_HOST="${HEADLAMP_PUBLIC_HOST:-headlamp.admin.${PLATFORM_BASE_DOMAIN}}"
HUBBLE_PUBLIC_HOST="${HUBBLE_PUBLIC_HOST:-hubble.admin.${PLATFORM_BASE_DOMAIN}}"
KYVERNO_PUBLIC_HOST="${KYVERNO_PUBLIC_HOST:-kyverno.admin.${PLATFORM_BASE_DOMAIN}}"
SENTIMENT_DEV_PUBLIC_HOST="${SENTIMENT_DEV_PUBLIC_HOST:-sentiment.dev.${PLATFORM_BASE_DOMAIN}}"
SENTIMENT_UAT_PUBLIC_HOST="${SENTIMENT_UAT_PUBLIC_HOST:-sentiment.uat.${PLATFORM_BASE_DOMAIN}}"
SUBNETCALC_DEV_PUBLIC_HOST="${SUBNETCALC_DEV_PUBLIC_HOST:-subnetcalc.dev.${PLATFORM_BASE_DOMAIN}}"
SUBNETCALC_UAT_PUBLIC_HOST="${SUBNETCALC_UAT_PUBLIC_HOST:-subnetcalc.uat.${PLATFORM_BASE_DOMAIN}}"
APIM_PUBLIC_HOST="${APIM_PUBLIC_HOST:-apim.admin.${PLATFORM_BASE_DOMAIN}}"
KEYCLOAK_PUBLIC_HOST="${KEYCLOAK_PUBLIC_HOST:-keycloak.${PLATFORM_BASE_DOMAIN}}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-platform}"
SSO_PUBLIC_URL="${SSO_PUBLIC_URL:-https://${KEYCLOAK_PUBLIC_HOST}/realms/${KEYCLOAK_REALM}}"
MCP_PUBLIC_HOST="${MCP_PUBLIC_HOST:-mcp.${PLATFORM_BASE_DOMAIN}}"
MCP_CONSOLE_PUBLIC_HOST="${MCP_CONSOLE_PUBLIC_HOST:-mcp-console.${PLATFORM_BASE_DOMAIN}}"
AGENTGATEWAY_AI_GATEWAY_PUBLIC_HOST="${AGENTGATEWAY_AI_GATEWAY_PUBLIC_HOST:-llm.${PLATFORM_BASE_DOMAIN}}"
AGENTGATEWAY_AI_GATEWAY_MODEL="${AGENTGATEWAY_AI_GATEWAY_MODEL:-}"
LANGFUSE_PUBLIC_HOST="${LANGFUSE_PUBLIC_HOST:-langfuse.admin.${PLATFORM_BASE_DOMAIN}}"
LANGFUSE_TRACE_CHAT_PUBLIC_HOST="${LANGFUSE_TRACE_CHAT_PUBLIC_HOST:-lf-chat.dev.${PLATFORM_BASE_DOMAIN}}"
LANGFUSE_TOOL_AGENT_PUBLIC_HOST="${LANGFUSE_TOOL_AGENT_PUBLIC_HOST:-lf-agent.dev.${PLATFORM_BASE_DOMAIN}}"
LANGFUSE_EVAL_RUNNER_PUBLIC_HOST="${LANGFUSE_EVAL_RUNNER_PUBLIC_HOST:-lf-evals.dev.${PLATFORM_BASE_DOMAIN}}"
ADMIN_ROUTE_ALLOWLIST_CIDRS="${ADMIN_ROUTE_ALLOWLIST_CIDRS:-}"
GATEWAY_TRUSTED_PROXY_CIDRS="${GATEWAY_TRUSTED_PROXY_CIDRS:-}"
ENABLE_CERT_MANAGER="${ENABLE_CERT_MANAGER:-true}"
ENABLE_ACTIONS_RUNNER="${ENABLE_ACTIONS_RUNNER:-true}"
ENABLE_APP_REPO_SENTIMENT="${ENABLE_APP_REPO_SENTIMENT:-false}"
ENABLE_APP_REPO_SUBNETCALC="${ENABLE_APP_REPO_SUBNETCALC:-false}"
ENABLE_SUBNETCALC_APIM_GATEWAY="${ENABLE_SUBNETCALC_APIM_GATEWAY:-true}"
ENABLE_APIM_SIMULATOR="${ENABLE_APIM_SIMULATOR:-false}"
ENABLE_AGENTGATEWAY_AI_GATEWAY="${ENABLE_AGENTGATEWAY_AI_GATEWAY:-false}"
ENABLE_LANGFUSE="${ENABLE_LANGFUSE:-false}"
ENABLE_LANGFUSE_DEMOS="${ENABLE_LANGFUSE_DEMOS:-false}"
ENABLE_PROMETHEUS="${ENABLE_PROMETHEUS:-false}"
ENABLE_ALERTMANAGER="${ENABLE_ALERTMANAGER:-false}"
ENABLE_GRAFANA="${ENABLE_GRAFANA:-false}"
ENABLE_VICTORIA_LOGS="${ENABLE_VICTORIA_LOGS:-false}"
ENABLE_OTEL_GATEWAY="${ENABLE_OTEL_GATEWAY:-false}"
ENABLE_OBSERVABILITY_AGENT="${ENABLE_OBSERVABILITY_AGENT:-false}"
ENABLE_METRICS_SERVER="${ENABLE_METRICS_SERVER:-false}"
ENABLE_EXTERNAL_SECRETS="${ENABLE_EXTERNAL_SECRETS:-false}"
ENABLE_PROGRESSIVE_DELIVERY="${ENABLE_PROGRESSIVE_DELIVERY:-false}"
ENABLE_HEADLAMP="${ENABLE_HEADLAMP:-false}"
ENABLE_SSO="${ENABLE_SSO:-false}"
ENABLE_BACKSTAGE="${ENABLE_BACKSTAGE:-true}"
HEADLAMP_CLUSTER_ROLE_BINDING_CREATE="${HEADLAMP_CLUSTER_ROLE_BINDING_CREATE:-true}"
HEADLAMP_OIDC_SKIP_TLS_VERIFY="${HEADLAMP_OIDC_SKIP_TLS_VERIFY:-true}"
HEADLAMP_OIDC_CLIENT_SECRET="${HEADLAMP_OIDC_CLIENT_SECRET:-}"
PREFER_EXTERNAL_WORKLOAD_IMAGES="${PREFER_EXTERNAL_WORKLOAD_IMAGES:-false}"
EXTERNAL_IMAGE_SENTIMENT_API="${EXTERNAL_IMAGE_SENTIMENT_API:-}"
EXTERNAL_IMAGE_SENTIMENT_AUTH_UI="${EXTERNAL_IMAGE_SENTIMENT_AUTH_UI:-}"
EXTERNAL_IMAGE_SUBNETCALC_API="${EXTERNAL_IMAGE_SUBNETCALC_API:-}"
EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR="${EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR:-}"
EXTERNAL_IMAGE_SUBNETCALC_FRONTEND="${EXTERNAL_IMAGE_SUBNETCALC_FRONTEND:-}"
PREFER_EXTERNAL_PLATFORM_IMAGES="${PREFER_EXTERNAL_PLATFORM_IMAGES:-false}"
EXTERNAL_PLATFORM_IMAGE_GRAFANA="${EXTERNAL_PLATFORM_IMAGE_GRAFANA:-}"
EXTERNAL_PLATFORM_IMAGE_IDP_CORE="${EXTERNAL_PLATFORM_IMAGE_IDP_CORE:-}"
EXTERNAL_PLATFORM_IMAGE_BACKSTAGE="${EXTERNAL_PLATFORM_IMAGE_BACKSTAGE:-}"
EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP="${EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP:-}"
HARDENED_IMAGE_REGISTRY="${HARDENED_IMAGE_REGISTRY:-dhi.io}"
AGENTGATEWAY_CHART_VERSION="${AGENTGATEWAY_CHART_VERSION:-$(tf_default_from_variables agentgateway_chart_version)}"
CERT_MANAGER_CHART_VERSION="${CERT_MANAGER_CHART_VERSION:-$(tf_default_from_variables cert_manager_chart_version)}"
GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-$(tf_default_from_variables grafana_chart_version)}"
GRAFANA_IMAGE_REGISTRY="${GRAFANA_IMAGE_REGISTRY:-$(tf_default_from_variables grafana_image_registry)}"
GRAFANA_IMAGE_REPOSITORY="${GRAFANA_IMAGE_REPOSITORY:-$(tf_default_from_variables grafana_image_repository)}"
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-$(tf_default_from_variables grafana_image_tag)}"
GRAFANA_SIDECAR_IMAGE_REGISTRY="${GRAFANA_SIDECAR_IMAGE_REGISTRY:-$(tf_default_from_variables grafana_sidecar_image_registry)}"
GRAFANA_SIDECAR_IMAGE_REPOSITORY="${GRAFANA_SIDECAR_IMAGE_REPOSITORY:-$(tf_default_from_variables grafana_sidecar_image_repository)}"
GRAFANA_SIDECAR_IMAGE_TAG="${GRAFANA_SIDECAR_IMAGE_TAG:-$(tf_default_from_variables grafana_sidecar_image_tag)}"
if [[ -z "${GRAFANA_VICTORIA_LOGS_PLUGIN_URL+x}" ]]; then
  GRAFANA_VICTORIA_LOGS_PLUGIN_URL="$(tf_default_from_variables grafana_victoria_logs_plugin_url)"
fi
GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS="${GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS:-$(tf_default_from_variables grafana_liveness_initial_delay_seconds)}"
HEADLAMP_CHART_VERSION="${HEADLAMP_CHART_VERSION:-$(tf_default_from_variables headlamp_chart_version)}"
METRICS_SERVER_CHART_VERSION="${METRICS_SERVER_CHART_VERSION:-$(tf_default_from_variables metrics_server_chart_version)}"
EXTERNAL_SECRETS_CHART_VERSION="${EXTERNAL_SECRETS_CHART_VERSION:-$(tf_default_from_variables external_secrets_chart_version)}"
KYVERNO_CHART_VERSION="${KYVERNO_CHART_VERSION:-$(tf_default_from_variables kyverno_chart_version)}"
OAUTH2_PROXY_CHART_VERSION="${OAUTH2_PROXY_CHART_VERSION:-$(tf_default_from_variables oauth2_proxy_chart_version)}"
OPENTELEMETRY_COLLECTOR_CHART_VERSION="${OPENTELEMETRY_COLLECTOR_CHART_VERSION:-$(tf_default_from_variables opentelemetry_collector_chart_version)}"
POLICY_REPORTER_CHART_VERSION="${POLICY_REPORTER_CHART_VERSION:-$(tf_default_from_variables policy_reporter_chart_version)}"
PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-$(tf_default_from_variables prometheus_chart_version)}"
VICTORIA_LOGS_CHART_VERSION="${VICTORIA_LOGS_CHART_VERSION:-$(tf_default_from_variables victoria_logs_chart_version)}"

command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v git >/dev/null 2>&1 || fail "git not found"
command -v helm >/dev/null 2>&1 || fail "helm not found"

GITEA_LOCAL_ACCESS_LOADED=0
tmp=""

load_gitea_local_access() {
  if [[ "${GITEA_LOCAL_ACCESS_LOADED}" == "1" ]]; then
    return 0
  fi

  # shellcheck source=/dev/null
  source "${STACK_DIR}/scripts/gitea-local-access.sh"
  GITEA_LOCAL_ACCESS_LOADED=1
}

cleanup() {
  local d="${tmp:-}"
  if [[ "${GITEA_LOCAL_ACCESS_LOADED}" == "1" ]] && declare -F gitea_local_access_cleanup >/dev/null 2>&1; then
    gitea_local_access_cleanup || true
  fi
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  return 0
}
trap cleanup EXIT

cleanup_tmp() {
  local d="${tmp:-}"
  if [[ -n "$d" && -d "$d" ]]; then
    rm -rf "$d"
  fi
  tmp=""
  return 0
}

parse_args() {
  :
}

wait_for_gitea() {
  local code
  for i in {1..120}; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 \
      "${GITEA_HTTP_BASE}/api/v1/version" 2>/dev/null || echo 000)"
    if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi
    echo "Waiting for Gitea API... ($i/120)" >&2
    sleep 2
  done
  fail "Gitea API not reachable at ${GITEA_HTTP_BASE}"
}

gitea_git_ssh_command() {
  local ssh_cmd

  printf -v ssh_cmd \
    'ssh -i %q -p %q -o IdentitiesOnly=yes -o IdentityAgent=none -o PreferredAuthentications=publickey -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' \
    "${SSH_PRIVATE_KEY_PATH}" \
    "${GITEA_SSH_PORT}"

  printf '%s\n' "${ssh_cmd}"
}

refresh_gitea_git_access() {
  load_gitea_local_access
  gitea_local_access_reset both
  : "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"
  : "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required after local access setup}"
  : "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required after local access setup}"
  wait_for_gitea
}

is_true() {
  case "${1}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

apim_effective() {
  is_true "${ENABLE_APIM_SIMULATOR}" || { is_true "${ENABLE_APP_REPO_SUBNETCALC}" && is_true "${ENABLE_SUBNETCALC_APIM_GATEWAY}"; }
}

IMAGE_REPO_OWNER="${GITEA_REPO_OWNER}"

replace_image_ref() {
  local file="$1"
  local image_name="$2"
  local new_image_ref="$3"

  if [[ -z "${new_image_ref}" || ! -f "${file}" ]]; then
    return 0
  fi

  local out
  out="$(mktemp)"
  sed -E "s|(image:[[:space:]]*)([^[:space:]]*/)?${image_name}:[^[:space:]]+|\1${new_image_ref}|g" "${file}" > "${out}"
  mv "${out}" "${file}"
}

rewrite_image_owner() {
  local file="$1"

  if [[ ! -f "${file}" || -z "${IMAGE_REPO_OWNER}" ]]; then
    return 0
  fi

  local image_name out current
  current="${file}"
  for image_name in \
    sentiment-api \
    sentiment-auth-ui \
    subnetcalc-api \
    subnetcalc-apim-simulator \
    platform-mcp \
    auth-chat \
    chatgpt-sim \
    langfuse-demos \
    subnetcalc-frontend; do
    out="$(mktemp)"
    sed -E \
      "s|(image:[[:space:]]*[^[:space:]]*/)[^/]+/(${image_name}:)|\\1${IMAGE_REPO_OWNER}/\\2|g" \
      "${current}" > "${out}"
    mv "${out}" "${current}"
  done
}

rewrite_hardened_registry() {
  local root_dir="$1"
  local file tmp_file

  if [[ -z "${HARDENED_IMAGE_REGISTRY}" || "${HARDENED_IMAGE_REGISTRY}" == "dhi.io" || ! -d "${root_dir}" ]]; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    tmp_file="$(mktemp)"
    sed "s|dhi\\.io/|${HARDENED_IMAGE_REGISTRY}/|g" "${file}" > "${tmp_file}"
    mv "${tmp_file}" "${file}"
  done < <(find "${root_dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)
}

rewrite_public_hostnames() {
  local root_dir="$1"
  local file tmp_file

  if [[ ! -d "${root_dir}" ]]; then
    return 0
  fi

  while IFS= read -r -d '' file; do
    tmp_file="$(mktemp)"
    sed \
      -e "s|argocd\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${ARGOCD_PUBLIC_HOST}|g" \
      -e "s|gitea\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${GITEA_PUBLIC_HOST}|g" \
      -e "s|grafana\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${GRAFANA_PUBLIC_HOST}|g" \
      -e "s|headlamp\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${HEADLAMP_PUBLIC_HOST}|g" \
      -e "s|hubble\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${HUBBLE_PUBLIC_HOST}|g" \
      -e "s|kyverno\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${KYVERNO_PUBLIC_HOST}|g" \
      -e "s|sentiment\\.dev\\.127\\.0\\.0\\.1\\.sslip\\.io|${SENTIMENT_DEV_PUBLIC_HOST}|g" \
      -e "s|sentiment\\.uat\\.127\\.0\\.0\\.1\\.sslip\\.io|${SENTIMENT_UAT_PUBLIC_HOST}|g" \
      -e "s|subnetcalc\\.dev\\.127\\.0\\.0\\.1\\.sslip\\.io|${SUBNETCALC_DEV_PUBLIC_HOST}|g" \
      -e "s|subnetcalc\\.uat\\.127\\.0\\.0\\.1\\.sslip\\.io|${SUBNETCALC_UAT_PUBLIC_HOST}|g" \
      -e "s|apim\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${APIM_PUBLIC_HOST}|g" \
      -e "s|https://keycloak\\.127\\.0\\.0\\.1\\.sslip\\.io/realms/platform|${SSO_PUBLIC_URL}|g" \
      -e "s|mcp-console\\.127\\.0\\.0\\.1\\.sslip\\.io|${MCP_CONSOLE_PUBLIC_HOST}|g" \
      -e "s|mcp\\.127\\.0\\.0\\.1\\.sslip\\.io|${MCP_PUBLIC_HOST}|g" \
      -e "s|llm\\.127\\.0\\.0\\.1\\.sslip\\.io|${AGENTGATEWAY_AI_GATEWAY_PUBLIC_HOST}|g" \
      -e "s|langfuse\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io|${LANGFUSE_PUBLIC_HOST}|g" \
      -e "s|lf-chat\\.dev\\.127\\.0\\.0\\.1\\.sslip\\.io|${LANGFUSE_TRACE_CHAT_PUBLIC_HOST}|g" \
      -e "s|lf-agent\\.dev\\.127\\.0\\.0\\.1\\.sslip\\.io|${LANGFUSE_TOOL_AGENT_PUBLIC_HOST}|g" \
      -e "s|lf-evals\\.dev\\.127\\.0\\.0\\.1\\.sslip\\.io|${LANGFUSE_EVAL_RUNNER_PUBLIC_HOST}|g" \
      -e "s|127\\.0\\.0\\.1\\.sslip\\.io|${PLATFORM_BASE_DOMAIN}|g" \
      "${file}" > "${tmp_file}"
    mv "${tmp_file}" "${file}"
  done < <(find "${root_dir}" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) -print0)
}

render_platform_gateway_proxy_config() {
  local root_dir="$1"
  local nginxproxy_file="${root_dir}/apps/platform-gateway/nginxproxy.yaml"
  local trusted_proxy_block=""
  local cidr

  [[ -d "${root_dir}/apps/platform-gateway" ]] || return 0

  if [[ -n "${GATEWAY_TRUSTED_PROXY_CIDRS}" ]]; then
    trusted_proxy_block="  rewriteClientIP:"$'\n'
    trusted_proxy_block="${trusted_proxy_block}    mode: XForwardedFor"$'\n'
    trusted_proxy_block="${trusted_proxy_block}    setIPRecursively: true"$'\n'
    trusted_proxy_block="${trusted_proxy_block}    trustedAddresses:"$'\n'
    IFS=',' read -r -a cidrs <<< "${GATEWAY_TRUSTED_PROXY_CIDRS}"
    for cidr in "${cidrs[@]}"; do
      cidr="$(printf '%s' "${cidr}" | xargs)"
      [[ -n "${cidr}" ]] || continue
      trusted_proxy_block="${trusted_proxy_block}      - type: CIDR"$'\n'
      trusted_proxy_block="${trusted_proxy_block}        value: ${cidr}"$'\n'
    done
  fi

  cat > "${nginxproxy_file}" <<EOF
apiVersion: gateway.nginx.org/v1alpha2
kind: NginxProxy
metadata:
  name: platform-gateway-proxy-config
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  labels:
    app.kubernetes.io/name: platform-gateway-proxy-config
spec:
  kubernetes:
    service:
      type: NodePort
      # Map the Gateway listener port 443 to a fixed NodePort so Kind can expose it on a host port via extraPortMappings.
      nodePorts:
        - listenerPort: 443
          port: 30070
      # IMPORTANT for Kind: traffic enters on the control-plane node (extraPortMappings),
      # but the gateway Pod may schedule onto a worker node.
      # With externalTrafficPolicy=Local, the control-plane NodePort will blackhole connections.
      externalTrafficPolicy: Cluster
${trusted_proxy_block}
EOF
}

replace_literal() {
  local file="$1"
  local from="$2"
  local to="$3"

  [[ -f "${file}" ]] || return 0

  local out
  out="$(mktemp)"
  sed "s|${from}|${to}|g" "${file}" > "${out}"
  mv "${out}" "${file}"
}

replace_literal_block() {
  local file="$1"
  local from="$2"
  local to="$3"

  [[ -f "${file}" ]] || return 0

  FILE_PATH="${file}" FROM_LITERAL="${from}" TO_LITERAL="${to}" perl -0pi -e '
    my $from = $ENV{"FROM_LITERAL"};
    my $to = $ENV{"TO_LITERAL"};
    s/\Q$from\E/$to/g;
  ' "${file}"
}

parse_image_ref() {
  local image_ref="$1"
  local __registry_var="$2"
  local __repository_var="$3"
  local __tag_var="$4"
  local repo tag registry repository

  repo="${image_ref%:*}"
  tag="${image_ref##*:}"

  if [[ -z "${image_ref}" || "${repo}" == "${image_ref}" || -z "${repo}" || -z "${tag}" || "${repo}" != */* ]]; then
    fail "invalid image ref '${image_ref}'"
  fi

  registry="${repo%%/*}"
  repository="${repo#*/}"

  if [[ -z "${registry}" || -z "${repository}" ]]; then
    fail "invalid image ref '${image_ref}'"
  fi

  printf -v "${__registry_var}" '%s' "${registry}"
  printf -v "${__repository_var}" '%s' "${repository}"
  printf -v "${__tag_var}" '%s' "${tag}"
}

join_by() {
  local delimiter="$1"
  shift

  local out=""
  local item
  for item in "$@"; do
    [[ -n "${item}" ]] || continue
    if [[ -z "${out}" ]]; then
      out="${item}"
    else
      out="${out}${delimiter}${item}"
    fi
  done

  printf '%s\n' "${out}"
}

strip_wrapping_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s\n' "${value}"
}

yaml_scalar_for_key() {
  local file="$1"
  local key="$2"
  local value=""

  [[ -f "${file}" ]] || return 0

  value="$(sed -nE "s/^[[:space:]]*${key}:[[:space:]]*(.+)[[:space:]]*$/\\1/p" "${file}" | head -n 1 | xargs)"
  strip_wrapping_quotes "${value}"
}

chart_version_override_for_name() {
  local chart="$1"

  case "${chart}" in
    agentgateway) printf '%s\n' "${AGENTGATEWAY_CHART_VERSION}" ;;
    agentgateway-crds) printf '%s\n' "${AGENTGATEWAY_CHART_VERSION}" ;;
    argo-rollouts) printf '%s\n' "2.40.5" ;;
    cert-manager) printf '%s\n' "${CERT_MANAGER_CHART_VERSION}" ;;
    external-secrets) printf '%s\n' "${EXTERNAL_SECRETS_CHART_VERSION}" ;;
    grafana) printf '%s\n' "${GRAFANA_CHART_VERSION}" ;;
    headlamp) printf '%s\n' "${HEADLAMP_CHART_VERSION}" ;;
    metrics-server) printf '%s\n' "${METRICS_SERVER_CHART_VERSION}" ;;
    kyverno) printf '%s\n' "${KYVERNO_CHART_VERSION}" ;;
    oauth2-proxy) printf '%s\n' "${OAUTH2_PROXY_CHART_VERSION}" ;;
    opentelemetry-collector) printf '%s\n' "${OPENTELEMETRY_COLLECTOR_CHART_VERSION}" ;;
    policy-reporter) printf '%s\n' "${POLICY_REPORTER_CHART_VERSION}" ;;
    prometheus) printf '%s\n' "${PROMETHEUS_CHART_VERSION}" ;;
    victoria-logs-single) printf '%s\n' "${VICTORIA_LOGS_CHART_VERSION}" ;;
    *) printf '%s\n' "" ;;
  esac
}

assert_pinned_chart_version() {
  local chart="$1"
  local version="$2"

  case "${version}" in
    ""|"*"|HEAD|head|main|master)
      fail "chart ${chart} must use a pinned version, got '${version}'"
      ;;
  esac
}

vendor_chart() {
  local repo_url="$1"
  local chart="$2"
  local version="$3"
  local vendor_root="$4"
  local repo_name
  local status
  local tmp_registry_dir

  assert_pinned_chart_version "${chart}" "${version}"
  mkdir -p "${vendor_root}"
  rm -rf "${vendor_root:?}/${chart}"
  if [[ "${repo_url}" == "cr.agentgateway.dev/charts" || "${repo_url}" == "ghcr.io/kgateway-dev/charts" ]]; then
    local oci_repo="oci://${repo_url}/${chart}"
    tmp_registry_dir="$(mktemp -d)"
    set +e
    DOCKER_CONFIG="${tmp_registry_dir}" \
      helm pull "${oci_repo}" --version "${version}" --untar --untardir "${vendor_root}" >/dev/null
    status=$?
    set -e
    rmdir "${tmp_registry_dir}" >/dev/null 2>&1 || true
    return "${status}"
  fi
  repo_name="vendor-$(printf '%s' "${repo_url}" | cksum | awk '{print $1}')"
  helm repo add "${repo_name}" "${repo_url}" --force-update >/dev/null 2>&1 || true
  helm repo update "${repo_name}" >/dev/null 2>&1 || true
  helm pull "${repo_name}/${chart}" --version "${version}" --untar --untardir "${vendor_root}" >/dev/null
}

patch_vendored_headlamp_chart() {
  return 0
}

rewrite_argocd_app_to_vendored_chart() {
  local app_file="$1"
  local chart_path="$2"

  [[ -f "${app_file}" ]] || return 0

  local out
  out="$(mktemp)"
  awk -v repo_url="${POLICIES_REPO_URL_CLUSTER}" -v chart_path="${chart_path}" '
    /^[[:space:]]*repoURL:[[:space:]]*/ {
      sub(/repoURL:.*/, "repoURL: " repo_url)
      print
      next
    }
    /^[[:space:]]*chart:[[:space:]]*/ {
      next
    }
    /^[[:space:]]*targetRevision:[[:space:]]*/ {
      sub(/targetRevision:.*/, "targetRevision: main")
      print
      print "    path: " chart_path
      path_printed=1
      next
    }
    /^    path:[[:space:]]*/ {
      next
    }
    /^[[:space:]]*helm:[[:space:]]*/ && !path_printed {
      print "    path: " chart_path
      path_printed=1
      print
      next
    }
    { print }
  ' "${app_file}" > "${out}"
  mv "${out}" "${app_file}"
}

rewrite_external_argocd_apps_to_vendored_charts() {
  local apps_dir="$1"
  local vendor_root="$2"
  local app_file repo_url chart version chart_path version_override

  [[ -d "${apps_dir}" ]] || return 0

  while IFS= read -r app_file; do
    repo_url="$(yaml_scalar_for_key "${app_file}" "repoURL")"
    chart="$(yaml_scalar_for_key "${app_file}" "chart")"
    version="$(yaml_scalar_for_key "${app_file}" "targetRevision")"

    if [[ -z "${repo_url}" || -z "${chart}" ]]; then
      continue
    fi

    if [[ "${repo_url}" == "https://dl.gitea.io/charts/" ]]; then
      continue
    fi

    version_override="$(chart_version_override_for_name "${chart}")"
    if [[ -n "${version_override}" ]]; then
      version="${version_override}"
    fi

    assert_pinned_chart_version "${chart}" "${version}"
    vendor_chart "${repo_url}" "${chart}" "${version}" "${vendor_root}"
    chart_path="apps/vendor/charts/${chart}"
    rewrite_argocd_app_to_vendored_chart "${app_file}" "${chart_path}"
  done < <(find "${apps_dir}" -maxdepth 1 -type f -name '*.yaml' | sort)
}

vendor_direct_tf_only_charts() {
  local vendor_root="$1"

  vendor_chart "https://oauth2-proxy.github.io/manifests" "oauth2-proxy" "${OAUTH2_PROXY_CHART_VERSION}" "${vendor_root}"
  vendor_chart "https://kubernetes-sigs.github.io/headlamp/" "headlamp" "${HEADLAMP_CHART_VERSION}" "${vendor_root}"
  vendor_chart "https://kubernetes-sigs.github.io/metrics-server/" "metrics-server" "${METRICS_SERVER_CHART_VERSION}" "${vendor_root}"
  if is_true "${ENABLE_EXTERNAL_SECRETS}"; then
    vendor_chart "https://charts.external-secrets.io" "external-secrets" "${EXTERNAL_SECRETS_CHART_VERSION}" "${vendor_root}"
  fi
  patch_vendored_headlamp_chart "${vendor_root}"
}

apply_external_workload_images() {
  local workload_file="$1"
  local scope env_name contract_key image_name manifest_group image_ref

  if ! is_true "${PREFER_EXTERNAL_WORKLOAD_IMAGES}"; then
    return 0
  fi

  while IFS='|' read -r scope env_name contract_key image_name manifest_group; do
    [[ "${scope}" == "workload" ]] || continue
    eval "image_ref=\"\${${env_name}:-}\""
    replace_image_ref "${workload_file}" "${image_name}" "${image_ref}"
  done < <(render_external_image_inputs)
}

infer_external_platform_cache_ref() {
  local image_name="$1"

  case "${EXTERNAL_PLATFORM_IMAGE_GRAFANA}" in
    */platform/grafana-victorialogs:*)
      printf '%s/platform/%s:latest\n' "${EXTERNAL_PLATFORM_IMAGE_GRAFANA%%/platform/grafana-victorialogs:*}" "${image_name}"
      ;;
  esac
}

apply_external_platform_images() {
  local root_dir="$1"
  local idp_manifest="${root_dir}/apps/idp/all.yaml"
  local mcp_manifest="${root_dir}/apps/mcp/all.yaml"
  local auth_chat_manifest="${root_dir}/apps/auth-chat/all.yaml"
  local chatgpt_manifest="${root_dir}/apps/chatgpt-sim/all.yaml"
  local langfuse_demos_manifest="${root_dir}/apps/langfuse-demos/all.yaml"
  local scope env_name contract_key image_name manifest_group image_ref manifest_file

  if ! is_true "${PREFER_EXTERNAL_PLATFORM_IMAGES}"; then
    return 0
  fi

  if [[ -n "${EXTERNAL_PLATFORM_IMAGE_GRAFANA}" ]]; then
    parse_image_ref "${EXTERNAL_PLATFORM_IMAGE_GRAFANA}" GRAFANA_IMAGE_REGISTRY GRAFANA_IMAGE_REPOSITORY GRAFANA_IMAGE_TAG
    GRAFANA_VICTORIA_LOGS_PLUGIN_URL=""
  fi

  if [[ -z "${EXTERNAL_PLATFORM_IMAGE_IDP_CORE}" ]]; then
    EXTERNAL_PLATFORM_IMAGE_IDP_CORE="$(infer_external_platform_cache_ref idp-core)"
  fi
  if [[ -z "${EXTERNAL_PLATFORM_IMAGE_BACKSTAGE}" ]]; then
    EXTERNAL_PLATFORM_IMAGE_BACKSTAGE="$(infer_external_platform_cache_ref backstage)"
  fi

  while IFS='|' read -r scope env_name contract_key image_name manifest_group; do
    [[ "${scope}" == "platform" ]] || continue
    case "${manifest_group}" in
      idp)
        manifest_file="${idp_manifest}"
        eval "image_ref=\"\${${env_name}:-}\""
        ;;
      mcp)
        manifest_file="${mcp_manifest}"
        eval "image_ref=\"\${${env_name}:-}\""
        ;;
      auth-chat)
        manifest_file="${auth_chat_manifest}"
        eval "image_ref=\"\${${env_name}:-}\""
        ;;
      chatgpt)
        manifest_file="${chatgpt_manifest}"
        eval "image_ref=\"\${${env_name}:-}\""
        ;;
      langfuse-demos)
        manifest_file="${langfuse_demos_manifest}"
        eval "image_ref=\"\${${env_name}:-}\""
        ;;
      *)
        continue
        ;;
    esac
    replace_image_ref "${manifest_file}" "${image_name}" "${image_ref}"
  done < <(render_external_image_inputs)
}

render_grafana_application_manifest() {
  local app_file="$1"
  local plugins_block="        plugins: []"

  [[ -f "${app_file}" ]] || return 0

  if [[ -n "${GRAFANA_VICTORIA_LOGS_PLUGIN_URL}" ]]; then
    plugins_block=$'        plugins:\n          - '"${GRAFANA_VICTORIA_LOGS_PLUGIN_URL}"
  fi

  replace_literal "${app_file}" "__GRAFANA_IMAGE_REGISTRY__" "${GRAFANA_IMAGE_REGISTRY}"
  replace_literal "${app_file}" "__GRAFANA_IMAGE_REPOSITORY__" "${GRAFANA_IMAGE_REPOSITORY}"
  replace_literal "${app_file}" "__GRAFANA_IMAGE_TAG__" "${GRAFANA_IMAGE_TAG}"
  replace_literal "${app_file}" "__GRAFANA_SIDECAR_IMAGE_REGISTRY__" "${GRAFANA_SIDECAR_IMAGE_REGISTRY}"
  replace_literal "${app_file}" "__GRAFANA_SIDECAR_IMAGE_REPOSITORY__" "${GRAFANA_SIDECAR_IMAGE_REPOSITORY}"
  replace_literal "${app_file}" "__GRAFANA_SIDECAR_IMAGE_TAG__" "${GRAFANA_SIDECAR_IMAGE_TAG}"
  replace_literal_block "${app_file}" "__GRAFANA_PLUGINS_VALUES__" "${plugins_block}"
  replace_literal "${app_file}" "__GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS__" "${GRAFANA_LIVENESS_INITIAL_DELAY_SECONDS}"
  ensure_grafana_dashboard_provider_paths "${app_file}"
}

render_prometheus_application_manifest() {
  local app_file="$1"
  local out

  [[ -f "${app_file}" ]] || return 0
  is_true "${ENABLE_ALERTMANAGER}" || return 0

  out="$(mktemp)"
  awk -v hardened_registry="${HARDENED_IMAGE_REGISTRY}" '
    function print_alertmanager_block() {
      print "        alertmanager:"
      print "          enabled: true"
      print "          image:"
      print "            repository: " hardened_registry "/alertmanager"
      print "            tag: 0.31.1-debian13"
      print "          persistence:"
      print "            enabled: false"
      print "          resources:"
      print "            requests:"
      print "              cpu: 25m"
      print "              memory: 64Mi"
      print "            limits:"
      print "              cpu: 200m"
      print "              memory: 256Mi"
    }

    function print_alert_rules_block() {
      print "        serverFiles:"
      print "          alerting_rules.yml:"
      print "            groups:"
      print "              - name: platform-starter.rules"
      print "                rules:"
      print "                  - alert: PlatformPodCrashLooping"
      print "                    expr: sum by (namespace, pod, container) (rate(kube_pod_container_status_restarts_total{namespace!~\"kube-system|local-path-storage\",container!=\"POD\"}[5m])) > 0"
      print "                    for: 10m"
      print "                    labels:"
      print "                      severity: warning"
      print "                    annotations:"
      print "                      summary: \"Pod container is restarting repeatedly\""
      print "                      description: \"Container {{ $labels.container }} in pod {{ $labels.namespace }}/{{ $labels.pod }} has a sustained restart rate.\""
      print "                      runbook_url: \"https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformpodcrashlooping\""
      print "                  - alert: PlatformDeploymentReplicasUnavailable"
      print "                    expr: kube_deployment_status_replicas_unavailable{namespace!~\"kube-system|local-path-storage\"} > 0"
      print "                    for: 10m"
      print "                    labels:"
      print "                      severity: warning"
      print "                    annotations:"
      print "                      summary: \"Deployment has unavailable replicas\""
      print "                      description: \"Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has unavailable replicas for more than 10 minutes.\""
      print "                      runbook_url: \"https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformdeploymentreplicasunavailable\""
      print "                  - alert: PlatformPersistentVolumeClaimFilling"
      print "                    expr: (1 - (kubelet_volume_stats_available_bytes{namespace!=\"\"} / kubelet_volume_stats_capacity_bytes{namespace!=\"\"})) > 0.85"
      print "                    for: 10m"
      print "                    labels:"
      print "                      severity: warning"
      print "                    annotations:"
      print "                      summary: \"PersistentVolumeClaim usage is above 85%\""
      print "                      description: \"PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is more than 85% full.\""
      print "                      runbook_url: \"https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformpersistentvolumeclaimfilling\""
      print "                  - alert: PlatformNodeMemoryPressure"
      print "                    expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10"
      print "                    for: 10m"
      print "                    labels:"
      print "                      severity: warning"
      print "                    annotations:"
      print "                      summary: \"Node memory availability is below 10%\""
      print "                      description: \"Node exporter reports less than 10% memory available on {{ $labels.instance }}.\""
      print "                      runbook_url: \"https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformnodememorypressure\""
      print "                  - alert: PlatformCertificateExpiringSoon"
      print "                    expr: (certmanager_certificate_expiration_timestamp_seconds - time()) < 1209600"
      print "                    for: 30m"
      print "                    labels:"
      print "                      severity: warning"
      print "                    annotations:"
      print "                      summary: \"cert-manager certificate expires in less than 14 days\""
      print "                      description: \"Certificate {{ $labels.namespace }}/{{ $labels.name }} expires in less than 14 days.\""
      print "                      runbook_url: \"https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformcertificateexpiringsoon\""
    }

    /^[[:space:]]*serverFiles:[[:space:]]*$/ {
      has_server_files = 1
    }

    skip_alertmanager && /^[[:space:]]{8}[A-Za-z0-9_-]+:[[:space:]]*/ {
      skip_alertmanager = 0
    }

    skip_alertmanager {
      next
    }

    /^[[:space:]]{8}alertmanager:[[:space:]]*$/ {
      print_alertmanager_block()
      skip_alertmanager = 1
      next
    }

    /^[[:space:]]{8}extraScrapeConfigs:[[:space:]]*\|[[:space:]]*$/ && !has_server_files {
      print_alert_rules_block()
      has_server_files = 1
      print
      next
    }

    { print }
  ' "${app_file}" > "${out}"
  mv "${out}" "${app_file}"
}

ensure_grafana_dashboard_provider_paths() {
  local app_file="$1"

  [[ -f "${app_file}" ]] || return 0

  local out
  out="$(mktemp)"
  awk '
    function provider_path(name) {
      if (name == "default") return "/var/lib/grafana/dashboards/default"
      if (name == "kubernetes") return "/var/lib/grafana/dashboards/kubernetes"
      if (name == "cilium") return "/var/lib/grafana/dashboards/cilium"
      if (name == "argocd") return "/var/lib/grafana/dashboards/argocd"
      return ""
    }
    {
      if ($0 ~ /^[[:space:]]+- name: (default|kubernetes|cilium|argocd)$/) {
        current = $3
      }

      if ($0 ~ /^[[:space:]]+options:[[:space:]]*$/ && provider_path(current) != "") {
        print
        if ((getline next_line) > 0) {
          if (next_line ~ /^[[:space:]]+path:[[:space:]]+/) {
            print next_line
          } else {
            print "                  path: " provider_path(current)
            print next_line
          }
        } else {
          print "                  path: " provider_path(current)
        }
        next
      }

      print
    }
  ' "${app_file}" > "${out}"
  mv "${out}" "${app_file}"
}

remove_if_present() {
  local path="$1"
  if [[ -e "$path" ]]; then
    rm -f "$path"
  fi
}

remove_kustomization_entry() {
  local kustomization_file="$1"
  local resource_file="$2"

  if [[ ! -f "${kustomization_file}" ]]; then
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp)
  grep -Fv "  - ${resource_file}" "${kustomization_file}" > "${tmp_file}" || true
  mv "${tmp_file}" "${kustomization_file}"
}

add_kustomization_entry() {
  local kustomization_file="$1"
  local resource_file="$2"

  if [[ ! -f "${kustomization_file}" ]]; then
    return 0
  fi

  if grep -Fqx "  - ${resource_file}" "${kustomization_file}"; then
    return 0
  fi

  printf '  - %s\n' "${resource_file}" >> "${kustomization_file}"
}

render_image_signing_policy() {
  local policy_dir="$1"
  local policy_file="${policy_dir}/verify-local-registry-signatures.yaml"
  local kustomization_file="${policy_dir}/kustomization.yaml"
  local escaped_key=""

  if ! is_true "${ENABLE_IMAGE_SIGNING}"; then
    remove_if_present "${policy_file}"
    remove_kustomization_entry "${kustomization_file}" "verify-local-registry-signatures.yaml"
    return 0
  fi

  [[ -n "${IMAGE_SIGNING_PUBLIC_KEY}" ]] || fail "enable_image_signing=true but image_signing_public_key is empty; run a signing-enabled local image build first"
  [[ -f "${policy_file}" ]] || fail "missing image signing policy: ${policy_file}"

  escaped_key="$(printf '%s\n' "${IMAGE_SIGNING_PUBLIC_KEY}" | sed 's/^/                      /')"
  awk -v key="${escaped_key}" '
    $0 == "                      ${COSIGN_PUBLIC_KEY}" {
      print key
      next
    }
    { print }
  ' "${policy_file}" > "${policy_file}.tmp"
  mv "${policy_file}.tmp" "${policy_file}"
}

remove_referencegrant_service() {
  local file="$1"
  local service_name="$2"

  [[ -f "${file}" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v service_name="${service_name}" '
    /^[[:space:]]*-[[:space:]]*group:[[:space:]]*""[[:space:]]*$/ {
      line1 = $0
      if ((getline line2) > 0 && (getline line3) > 0) {
        if (line2 ~ /^[[:space:]]*kind:[[:space:]]*Service[[:space:]]*$/ &&
            line3 ~ ("^[[:space:]]*name:[[:space:]]*" service_name "[[:space:]]*$")) {
          next
        }
        print line1
        print line2
        print line3
        next
      }
    }
    { print }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

remove_yaml_document() {
  local file="$1"
  local kind="$2"
  local name="$3"

  [[ -f "${file}" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v wanted_kind="${kind}" -v wanted_name="${name}" '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    function flush_doc() {
      if (doc != "" && !(doc_kind == wanted_kind && doc_name == wanted_name)) {
        if (printed) {
          print "---"
        }
        printf "%s", doc
        printed = 1
      }
      doc = ""
      doc_kind = ""
      doc_name = ""
      in_metadata = 0
    }
    /^[[:space:]]*---[[:space:]]*$/ {
      flush_doc()
      next
    }
    {
      doc = doc $0 "\n"
      if ($0 ~ /^kind:[[:space:]]*/) {
        value = $0
        sub(/^kind:[[:space:]]*/, "", value)
        doc_kind = trim(value)
      }
      if ($0 ~ /^metadata:[[:space:]]*$/) {
        in_metadata = 1
        next
      }
      if (in_metadata && $0 ~ /^[^[:space:]]/) {
        in_metadata = 0
      }
      if (in_metadata && $0 ~ /^[[:space:]]+name:[[:space:]]*/) {
        value = $0
        sub(/^[[:space:]]+name:[[:space:]]*/, "", value)
        doc_name = trim(value)
      }
    }
    END {
      flush_doc()
    }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

remove_backstage_idp_resources() {
  local idp_manifest="$1"

  remove_yaml_document "${idp_manifest}" "ServiceAccount" "backstage"
  remove_yaml_document "${idp_manifest}" "ClusterRole" "backstage-kubernetes-reader"
  remove_yaml_document "${idp_manifest}" "ClusterRoleBinding" "backstage-kubernetes-reader"
  remove_yaml_document "${idp_manifest}" "Deployment" "backstage"
  remove_yaml_document "${idp_manifest}" "Service" "backstage"
}

remove_observability_targetref_route() {
  local file="$1"
  local route_name="$2"

  [[ -f "${file}" ]] || return 0

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v route_name="${route_name}" '
    /^[[:space:]]*-[[:space:]]*group:[[:space:]]*gateway\.networking\.k8s\.io[[:space:]]*$/ {
      line1 = $0
      if ((getline line2) > 0 && (getline line3) > 0) {
        if (line2 ~ /^[[:space:]]*kind:[[:space:]]*HTTPRoute[[:space:]]*$/ &&
            line3 ~ ("^[[:space:]]*name:[[:space:]]*" route_name "[[:space:]]*$")) {
          next
        }
        print line1
        print line2
        print line3
        next
      }
    }
    { print }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

render_otel_gateway_manifest() {
  local apps_dir="$1"
  local gateway_enabled="false"
  local prom_fanout="false"
  local victoria_logs_fanout="false"
  local destination="${apps_dir}/96-otel-collector-prometheus.application.yaml"
  local traces_exporters=()
  local metrics_exporters=()
  local logs_exporters=()
  local traces_exporters_csv=""
  local metrics_exporters_csv=""
  local logs_exporters_csv=""

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_VICTORIA_LOGS}"; then
    gateway_enabled="true"
  fi

  if is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}"; then
    prom_fanout="true"
  fi

  if is_true "${ENABLE_VICTORIA_LOGS}"; then
    victoria_logs_fanout="true"
  fi

  if ! is_true "${gateway_enabled}"; then
    remove_if_present "${destination}"
    return 0
  fi

  if is_true "${prom_fanout}"; then
    traces_exporters+=("spanmetrics")
    metrics_exporters+=("prometheus")
  fi

  if is_true "${victoria_logs_fanout}"; then
    logs_exporters+=("otlphttp/victoria-logs")
  fi

  if [[ "${#traces_exporters[@]}" -eq 0 ]]; then
    traces_exporters=("debug")
  fi

  if [[ "${#metrics_exporters[@]}" -eq 0 ]]; then
    metrics_exporters=("debug")
  fi

  if [[ "${#logs_exporters[@]}" -eq 0 ]]; then
    logs_exporters=("debug")
  fi

  traces_exporters_csv="$(join_by ", " "${traces_exporters[@]}")"
  metrics_exporters_csv="$(join_by ", " "${metrics_exporters[@]}")"
  logs_exporters_csv="$(join_by ", " "${logs_exporters[@]}")"

  cat > "${destination}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: otel-collector-prometheus
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "96"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
    chart: opentelemetry-collector
    targetRevision: ${OPENTELEMETRY_COLLECTOR_CHART_VERSION}
    helm:
      releaseName: otel-collector-prometheus
      values: |
        mode: deployment

        nameOverride: otel-collector
        fullnameOverride: otel-collector

        image:
          repository: otel/opentelemetry-collector-contrib

        replicaCount: 1

        service:
          enabled: true
          type: ClusterIP
EOF

  if is_true "${prom_fanout}"; then
    cat >> "${destination}" <<'EOF'
          annotations:
            prometheus.io/scrape: "true"
            prometheus.io/path: /metrics
            prometheus.io/port: "9464"
EOF
  fi

  cat >> "${destination}" <<EOF

        ports:
          otlp:
            enabled: true
            hostPort: 0
            containerPort: 4317
            servicePort: 4317
          otlp-http:
            enabled: true
            hostPort: 0
            containerPort: 4318
            servicePort: 4318
          metrics:
            enabled: ${prom_fanout}
            hostPort: 0
            containerPort: 9464
            servicePort: 9464
          jaeger-compact:
            enabled: false
          jaeger-thrift:
            enabled: false
          jaeger-grpc:
            enabled: false
          zipkin:
            enabled: false

        presets:
          kubernetesAttributes:
            enabled: true
          logsCollection:
            enabled: true
            includeCollectorLogs: false
            storeCheckpoints: true

        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 300m
            memory: 384Mi

        config:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318

          processors:
            batch:
              timeout: 1s
              send_batch_size: 1024
            memory_limiter:
              check_interval: 1s
              limit_percentage: 75
              spike_limit_percentage: 15
EOF

  if is_true "${prom_fanout}"; then
    cat >> "${destination}" <<'EOF'

          connectors:
            spanmetrics:
              histogram:
                unit: ms
              dimensions:
                - name: k8s.namespace.name
                - name: http.method
                - name: http.status_code
                - name: service.version
EOF
  fi

  cat >> "${destination}" <<'EOF'

          exporters:
EOF

  if is_true "${prom_fanout}"; then
    cat >> "${destination}" <<'EOF'
            prometheus:
              endpoint: 0.0.0.0:9464
              resource_to_telemetry_conversion:
                enabled: true
EOF
  fi

  if is_true "${victoria_logs_fanout}"; then
    cat >> "${destination}" <<'EOF'
            otlphttp/victoria-logs:
              logs_endpoint: http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428/insert/opentelemetry/v1/logs
EOF
  fi

  if [[ "${traces_exporters_csv}" == "debug" || "${metrics_exporters_csv}" == "debug" || "${logs_exporters_csv}" == "debug" ]]; then
    cat >> "${destination}" <<'EOF'
            debug:
              verbosity: basic
EOF
  fi

  cat >> "${destination}" <<EOF

          service:
            pipelines:
              traces:
                receivers: [otlp]
                processors: [memory_limiter, k8sattributes, batch]
                exporters: [${traces_exporters_csv}]
              metrics:
                receivers: [$(if is_true "${prom_fanout}"; then printf 'otlp, spanmetrics'; else printf 'otlp'; fi)]
                processors: [memory_limiter, k8sattributes, batch]
                exporters: [${metrics_exporters_csv}]
              logs:
                receivers: [filelog]
                processors: [memory_limiter, k8sattributes, batch]
                exporters: [${logs_exporters_csv}]
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
EOF
}

render_headlamp_application_manifest() {
  local apps_dir="$1"
  local destination="${apps_dir}/85-headlamp.application.yaml"
  local oidc_config_hash

  if ! is_true "${ENABLE_HEADLAMP}"; then
    remove_if_present "${destination}"
    return 0
  fi

  oidc_config_hash="$(printf '%s|%s|%s|%s' "${SSO_PUBLIC_URL:-}" "${HEADLAMP_PUBLIC_HOST:-}" "${HEADLAMP_OIDC_CLIENT_SECRET:-}" "${HEADLAMP_OIDC_SKIP_TLS_VERIFY:-}" | shasum -a 256 | awk '{print $1}')"

  cat > "${destination}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: headlamp
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "85"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: headlamp
    server: https://kubernetes.default.svc
  source:
    repoURL: ${POLICIES_REPO_URL_CLUSTER}
    targetRevision: main
    path: apps/vendor/charts/headlamp
    helm:
      releaseName: headlamp
      values: |
        service:
          port: 4466
        clusterRoleBinding:
          create: ${HEADLAMP_CLUSTER_ROLE_BINDING_CREATE:-true}
        config:
          watchPlugins: false
EOF

  if is_true "${ENABLE_SSO}"; then
    cat >> "${destination}" <<EOF
          oidc:
            clientID: headlamp
            clientSecret: "${HEADLAMP_OIDC_CLIENT_SECRET}"
            issuerURL: ${SSO_PUBLIC_URL}
            scopes: openid profile email groups
            callbackURL: https://${HEADLAMP_PUBLIC_HOST}/oidc-callback
          extraArgs:
            - -oidc-ca-file=/headlamp-ca/ca.crt
EOF
    if is_true "${HEADLAMP_OIDC_SKIP_TLS_VERIFY}"; then
      cat >> "${destination}" <<'EOF'
            - -oidc-skip-tls-verify
EOF
    fi
  fi

  cat >> "${destination}" <<EOF
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 128Mi
        probes:
          livenessProbe:
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          readinessProbe:
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
EOF

  if is_true "${ENABLE_SSO}"; then
    cat >> "${destination}" <<EOF
        env:
          - name: SSL_CERT_FILE
            value: /headlamp-ca/ca.crt
          - name: HEADLAMP_OIDC_CONFIG_HASH
            value: "${oidc_config_hash}"
        volumeMounts:
          - name: headlamp-ca
            mountPath: /headlamp-ca
            readOnly: true
        volumes:
          - name: headlamp-ca
            secret:
              secretName: mkcert-ca
              items:
                - key: ca.crt
                  path: ca.crt
EOF
  else
    cat >> "${destination}" <<'EOF'
        env: []
        volumeMounts: []
        volumes: []
EOF
  fi

  cat >> "${destination}" <<'EOF'
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
EOF
}

render_platform_gateway_routes_application_manifest() {
  local apps_dir="$1"
  local destination="${apps_dir}/50-platform-gateway-routes.application.yaml"
  local routes_path="apps/platform-gateway-routes"

  if is_true "${ENABLE_SSO}"; then
    routes_path="apps/platform-gateway-routes-sso"
  fi

  if [[ ! -f "${destination}" ]]; then
    return 0
  fi

  sed -i.bak -E "s|^([[:space:]]*)path: apps/platform-gateway-routes(-sso)?[[:space:]]*$|\\1path: ${routes_path}|" "${destination}"
  rm -f "${destination}.bak"
}

prune_argocd_app_manifests() {
  local apps_dir="$1"
  local otel_gateway_enabled="false"
  local observability_enabled="false"

  if is_true "${ENABLE_OTEL_GATEWAY}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_VICTORIA_LOGS}"; then
    otel_gateway_enabled="true"
  fi

  if is_true "${otel_gateway_enabled}" || is_true "${ENABLE_PROMETHEUS}" || is_true "${ENABLE_GRAFANA}" || is_true "${ENABLE_VICTORIA_LOGS}"; then
    observability_enabled="true"
  fi

  render_otel_gateway_manifest "${apps_dir}"
  render_headlamp_application_manifest "${apps_dir}"
  render_platform_gateway_routes_application_manifest "${apps_dir}"

  if ! is_true "${ENABLE_POLICIES}"; then
    remove_if_present "${apps_dir}/31-policy-reporter.application.yaml"
    remove_if_present "${apps_dir}/20-kyverno.application.yaml"
    remove_if_present "${apps_dir}/30-kyverno-policies.application.yaml"
    remove_if_present "${apps_dir}/40-cilium-policies.application.yaml"
  fi

  if ! is_true "${ENABLE_CERT_MANAGER}"; then
    remove_if_present "${apps_dir}/001-cert-manager.application.yaml"
  fi

  if ! is_true "${ENABLE_GATEWAY_TLS}"; then
    remove_if_present "${apps_dir}/002-nginx-gateway-fabric.application.yaml"
    remove_if_present "${apps_dir}/003-platform-gateway.application.yaml"
    remove_if_present "${apps_dir}/10-cert-manager-config.application.yaml"
    remove_if_present "${apps_dir}/50-platform-gateway-routes.application.yaml"
  fi

  if ! is_true "${ENABLE_ACTIONS_RUNNER}"; then
    remove_if_present "${apps_dir}/60-gitea-actions-runner.application.yaml"
  fi

  if ! is_true "${ENABLE_SSO}"; then
    remove_if_present "${apps_dir}/78-idp.application.yaml"
  fi

  if ! is_true "${ENABLE_SSO}" || { ! apim_effective && ! is_true "${ENABLE_AGENTGATEWAY_AI_GATEWAY}"; }; then
    remove_if_present "${apps_dir}/79-mcp.application.yaml"
    remove_if_present "${apps_dir}/80-auth-chat.application.yaml"
    remove_if_present "${apps_dir}/80-chatgpt-sim.application.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SENTIMENT}" && ! is_true "${ENABLE_APP_REPO_SUBNETCALC}"; then
    remove_if_present "${apps_dir}/74-dev.application.yaml"
    remove_if_present "${apps_dir}/76-uat.application.yaml"
  fi

  if ! apim_effective; then
    remove_if_present "${apps_dir}/72-apim.application.yaml"
  fi

  if ! is_true "${ENABLE_AGENTGATEWAY_AI_GATEWAY}"; then
    remove_if_present "${apps_dir}/68-agentgateway-crds.application.yaml"
    remove_if_present "${apps_dir}/69-agentgateway.application.yaml"
    remove_if_present "${apps_dir}/73-agentgateway-ai-gateway.application.yaml"
  fi

  if ! is_true "${ENABLE_LANGFUSE}"; then
    remove_if_present "${apps_dir}/81-langfuse.application.yaml"
  fi

  if ! is_true "${ENABLE_LANGFUSE_DEMOS}"; then
    remove_if_present "${apps_dir}/82-langfuse-demos.application.yaml"
  fi

  if ! is_true "${observability_enabled}"; then
    remove_if_present "${apps_dir}/80-observability.namespace.yaml"
    remove_if_present "${apps_dir}/90-prometheus.application.yaml"
    remove_if_present "${apps_dir}/92-victoria-logs.application.yaml"
    remove_if_present "${apps_dir}/95-grafana.application.yaml"
    remove_if_present "${apps_dir}/96-otel-collector-prometheus.application.yaml"
    remove_if_present "${apps_dir}/110-grafana-ui-nodeport.service.yaml"
  fi

  if ! is_true "${ENABLE_PROMETHEUS}"; then
    remove_if_present "${apps_dir}/90-prometheus.application.yaml"
  fi

  if ! is_true "${ENABLE_GRAFANA}"; then
    remove_if_present "${apps_dir}/95-grafana.application.yaml"
    remove_if_present "${apps_dir}/110-grafana-ui-nodeport.service.yaml"
  fi

  if ! is_true "${ENABLE_VICTORIA_LOGS}"; then
    remove_if_present "${apps_dir}/92-victoria-logs.application.yaml"
  fi

  if ! is_true "${ENABLE_OBSERVABILITY_AGENT}"; then
    remove_if_present "${apps_dir}/100-otel-collector-agent.application.yaml"
  fi

  if ! is_true "${ENABLE_HEADLAMP}"; then
    remove_if_present "${apps_dir}/85-headlamp.application.yaml"
  fi

  if ! is_true "${ENABLE_METRICS_SERVER}"; then
    remove_if_present "${apps_dir}/88-metrics-server.application.yaml"
  fi

  if ! is_true "${ENABLE_EXTERNAL_SECRETS}"; then
    remove_if_present "${apps_dir}/86-external-secrets.application.yaml"
    remove_if_present "${apps_dir}/87-eso-demo.application.yaml"
    rm -rf "$(dirname "${apps_dir}")/eso-demo"
  fi

  if ! is_true "${ENABLE_PROGRESSIVE_DELIVERY}"; then
    remove_if_present "${apps_dir}/86-argo-rollouts.namespace.yaml"
    remove_if_present "${apps_dir}/87-argo-rollouts.application.yaml"
  fi

  if ! is_true "${ENABLE_OTEL_GATEWAY}" && ! is_true "${ENABLE_PROMETHEUS}" && ! is_true "${ENABLE_GRAFANA}" && ! is_true "${ENABLE_VICTORIA_LOGS}" && ! is_true "${ENABLE_OBSERVABILITY_AGENT}"; then
    remove_if_present "${apps_dir}/80-observability.namespace.yaml"
  fi
}

prune_gateway_routes_manifests() {
  local routes_dir="$1"
  local kustomization_file="${routes_dir}/kustomization.yaml"

  if ! is_true "${ENABLE_BACKSTAGE}"; then
    remove_if_present "${routes_dir}/httproute-portal.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-portal.yaml"
    remove_referencegrant_service "${routes_dir}/referencegrant-sso.yaml" "oauth2-proxy-backstage"
  fi

  if ! is_true "${ENABLE_HUBBLE}"; then
    remove_if_present "${routes_dir}/httproute-hubble.yaml"
    remove_if_present "${routes_dir}/referencegrant-hubble.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-hubble.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-hubble.yaml"
    remove_referencegrant_service "${routes_dir}/referencegrant-sso.yaml" "oauth2-proxy-hubble"
    remove_observability_targetref_route "${routes_dir}/observabilitypolicy-tracing.yaml" "hubble"
  fi

  if ! is_true "${ENABLE_POLICIES}" || ! is_true "${ENABLE_GATEWAY_TLS}"; then
    remove_if_present "${routes_dir}/httproute-kyverno.yaml"
    remove_if_present "${routes_dir}/referencegrant-policy-reporter.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-kyverno.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-policy-reporter.yaml"
  fi

  if ! is_true "${ENABLE_HEADLAMP}"; then
    remove_if_present "${routes_dir}/httproute-headlamp.yaml"
    remove_if_present "${routes_dir}/referencegrant-headlamp.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-headlamp.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-headlamp.yaml"
  fi

  if ! is_true "${ENABLE_GRAFANA}"; then
    remove_if_present "${routes_dir}/httproute-grafana.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-grafana.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SENTIMENT}"; then
    remove_if_present "${routes_dir}/httproute-sentiment-dev.yaml"
    remove_if_present "${routes_dir}/httproute-sentiment-uat.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-sentiment-dev.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-sentiment-uat.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SUBNETCALC}"; then
    remove_if_present "${routes_dir}/httproute-subnetcalc-dev.yaml"
    remove_if_present "${routes_dir}/httproute-subnetcalc-uat.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-subnetcalc-dev.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-subnetcalc-uat.yaml"
  fi

  if ! is_true "${ENABLE_APP_REPO_SUBNETCALC}" || ! is_true "${ENABLE_PROGRESSIVE_DELIVERY}"; then
    remove_if_present "${routes_dir}/httproute-subnetcalc-frontend-dev.yaml"
    remove_if_present "${routes_dir}/referencegrant-dev-subnetcalc-frontend.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-subnetcalc-frontend-dev.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-dev-subnetcalc-frontend.yaml"
  fi

  if ! apim_effective; then
    remove_if_present "${routes_dir}/httproute-apim.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-apim.yaml"
    remove_referencegrant_service "${routes_dir}/referencegrant-sso.yaml" "oauth2-proxy-apim"
    remove_if_present "${routes_dir}/referencegrant-apim.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-apim.yaml"
  fi

  if ! is_true "${ENABLE_AGENTGATEWAY_AI_GATEWAY}"; then
    remove_if_present "${routes_dir}/httproute-agentgateway-ai-gateway.yaml"
    remove_if_present "${routes_dir}/referencegrant-agentgateway-ai-gateway.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-agentgateway-ai-gateway.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-agentgateway-ai-gateway.yaml"
  fi

  if ! is_true "${ENABLE_LANGFUSE}"; then
    remove_if_present "${routes_dir}/httproute-langfuse.yaml"
    remove_kustomization_entry "${kustomization_file}" "httproute-langfuse.yaml"
    remove_referencegrant_service "${routes_dir}/referencegrant-sso.yaml" "oauth2-proxy-langfuse"
  fi

  if ! is_true "${ENABLE_LANGFUSE_DEMOS}"; then
    for route in langfuse-trace-chat langfuse-tool-agent langfuse-eval-runner; do
      remove_if_present "${routes_dir}/httproute-${route}.yaml"
      remove_kustomization_entry "${kustomization_file}" "httproute-${route}.yaml"
    done
    remove_if_present "${routes_dir}/referencegrant-sso-langfuse-demos.yaml"
    remove_kustomization_entry "${kustomization_file}" "referencegrant-sso-langfuse-demos.yaml"
  fi
}

route_has_oauth2_proxy_backend() {
  local route_file="$1"
  grep -qE '^[[:space:]]*name:[[:space:]]*oauth2-proxy-' "${route_file}"
}

route_primary_hostname() {
  local route_file="$1"
  awk '
    /^[[:space:]]*hostnames:[[:space:]]*$/ { in_hostnames=1; next }
    in_hostnames && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
      print
      exit
    }
    in_hostnames && /^[^[:space:]]/ { exit }
  ' "${route_file}"
}

render_gateway_route_admin_allowlist() {
  local routes_dir="$1"
  local filter_file="${routes_dir}/snippetsfilter-admin-allowlist.yaml"
  local allowlist_snippet=""
  local cidr

  [[ -d "${routes_dir}" ]] || return 0

  if [[ -n "${ADMIN_ROUTE_ALLOWLIST_CIDRS}" ]]; then
    IFS=',' read -r -a cidrs <<< "${ADMIN_ROUTE_ALLOWLIST_CIDRS}"
    for cidr in "${cidrs[@]}"; do
      cidr="$(printf '%s' "${cidr}" | xargs)"
      [[ -n "${cidr}" ]] || continue
      allowlist_snippet="${allowlist_snippet}        allow ${cidr};"$'\n'
    done
    allowlist_snippet="${allowlist_snippet}        deny all;"
  else
    allowlist_snippet="        allow all;"
  fi

  cat > "${filter_file}" <<EOF
apiVersion: gateway.nginx.org/v1alpha1
kind: SnippetsFilter
metadata:
  name: admin-allowlist
  namespace: gateway-routes
spec:
  snippets:
    - context: http.server.location
      value: |
${allowlist_snippet}
EOF
}

render_gateway_route_forwarded_headers() {
  local routes_dir="$1"
  local route_file host tmp_file

  [[ "${GATEWAY_HTTPS_HOST_PORT}" != "443" ]] || return 0
  [[ -d "${routes_dir}" ]] || return 0

  while IFS= read -r -d '' route_file; do
    route_has_oauth2_proxy_backend "${route_file}" || continue
    host="$(route_primary_hostname "${route_file}")"
    [[ -n "${host}" ]] || continue

    tmp_file="$(mktemp)"
    awk -v host="${host}" -v port="${GATEWAY_HTTPS_HOST_PORT}" '
      /^[[:space:]]*filters:[[:space:]]*$/ && !injected {
        print
        print "        - type: RequestHeaderModifier"
        print "          requestHeaderModifier:"
        print "            set:"
        print "              - name: X-Forwarded-Host"
        print "                value: " host ":" port
        print "              - name: X-Forwarded-Port"
        print "                value: \"" port "\""
        print "              - name: X-Forwarded-Proto"
        print "                value: https"
        injected=1
        next
      }
      /^[[:space:]]*backendRefs:[[:space:]]*$/ && !injected {
        print "      filters:"
        print "        - type: RequestHeaderModifier"
        print "          requestHeaderModifier:"
        print "            set:"
        print "              - name: X-Forwarded-Host"
        print "                value: " host ":" port
        print "              - name: X-Forwarded-Port"
        print "                value: \"" port "\""
        print "              - name: X-Forwarded-Proto"
        print "                value: https"
        injected=1
      }
      { print }
    ' "${route_file}" > "${tmp_file}"
    mv "${tmp_file}" "${route_file}"
  done < <(find "${routes_dir}" -maxdepth 1 -type f -name 'httproute-*.yaml' -print0)
}

configure_subnetcalc_direct_api() {
  local repo_dir="$1"
  local workloads_file="${repo_dir}/apps/workloads/base/all.yaml"
  local policy_file="${repo_dir}/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml"

  is_true "${ENABLE_APP_REPO_SUBNETCALC}" || return 0
  ! is_true "${ENABLE_SUBNETCALC_APIM_GATEWAY}" || return 0

  if [[ -f "${workloads_file}" ]]; then
    perl -0pi -e 's|(name: subnetcalc-router-nginx.*?proxy_pass )http://subnetcalc-apim-simulator\.apim\.svc\.cluster\.local:8000;|${1}http://subnetcalc-api:8000;|s' "${workloads_file}"
    perl -0pi -e 's|("Subnet router","detail":"dev/uat nginx router","role":"Routes UI and API traffic"},\{"label":")APIM simulator","detail":"apim/subnetcalc-apim-simulator","role":"Gateway auth, policy, tracing"|${1}Subnetcalc API","detail":"subnetcalc-api service","role":"Direct local IDP sample API"|g' "${workloads_file}"
  fi

  if [[ -f "${policy_file}" ]]; then
    perl -0pi -e '
      s/The router sends browser API traffic through the shared APIM simulator\./The router sends browser API traffic directly to the subnetcalc API./g;
      s/The subnetcalc API receives browser traffic only from the shared APIM simulator\./The subnetcalc API receives browser traffic only from the subnetcalc router./g;
      s/"k8s:io\.kubernetes\.pod\.namespace": apim\n//g;
      s/"k8s:tier": gateway\n            "k8s:app\.kubernetes\.io\/name": subnetcalc-apim-simulator/"k8s:tier": backend\n            "k8s:app.kubernetes.io\/name": subnetcalc-api/;
      s/"k8s:tier": gateway\n            "k8s:app\.kubernetes\.io\/name": subnetcalc-apim-simulator/"k8s:tier": gateway\n            "k8s:app.kubernetes.io\/name": subnetcalc-router/;
      s/port: "8000"/port: "8080"/;
    ' "${policy_file}"
  fi
}

configure_progressive_delivery() {
  local repo_dir="$1"
  local kustomization_file="${repo_dir}/apps/dev/kustomization.yaml"

  is_true "${ENABLE_PROGRESSIVE_DELIVERY}" || return 0
  is_true "${ENABLE_APP_REPO_SUBNETCALC}" || return 0
  [[ -f "${kustomization_file}" ]] || return 0

  if ! grep -Fq "subnetcalc-router-gateway-canary-patch.yaml" "${kustomization_file}"; then
    if grep -Eq '^patches:' "${kustomization_file}"; then
      cat >>"${kustomization_file}" <<'EOF'
  - path: subnetcalc-router-gateway-canary-patch.yaml
EOF
    else
      cat >>"${kustomization_file}" <<'EOF'
patches:
  - path: subnetcalc-router-gateway-canary-patch.yaml
EOF
    fi
  fi

  if grep -Fq "subnetcalc-frontend-rollout-patch.yaml" "${kustomization_file}"; then
    return 0
  fi

  if ! grep -Fq "subnetcalc-frontend-canary-service.yaml" "${kustomization_file}"; then
    perl -0pi -e 's|(resources:\n(?:  - .+\n)+)|${1}  - subnetcalc-frontend-canary-service.yaml\n|' "${kustomization_file}"
  fi

  if grep -Eq '^patches:' "${kustomization_file}"; then
    cat >>"${kustomization_file}" <<'EOF'
  - path: subnetcalc-frontend-rollout-patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: subnetcalc-frontend
EOF
  else
    cat >>"${kustomization_file}" <<'EOF'
patches:
  - path: subnetcalc-frontend-rollout-patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: subnetcalc-frontend
EOF
  fi
}

repo_exists_for_owner() {
  local owner="$1"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${owner}/${GITEA_REPO_NAME}" || echo 000)
  [[ "$code" == "200" ]]
}

ensure_org_exists() {
  if ! is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    return 0
  fi

  local code payload
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)

  if [[ "${code}" == "200" ]]; then
    return 0
  fi

  payload=$(cat <<EOF
{"username":"${GITEA_REPO_OWNER}"}
EOF
)

  echo "Gitea org '${GITEA_REPO_OWNER}' is missing; creating it before syncing repos" >&2
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs" || echo 000)

  if [[ "${code}" != "201" && "${code}" != "409" && "${code}" != "422" ]]; then
    fail "create org '${GITEA_REPO_OWNER}' returned HTTP ${code}"
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}" || echo 000)
  [[ "${code}" == "200" ]] || fail "organization '${GITEA_REPO_OWNER}' is still unavailable after create attempt (HTTP ${code})"
}

transfer_repo_if_needed() {
  if ! is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    return 0
  fi

  if [[ -z "${GITEA_REPO_OWNER_FALLBACK}" ]]; then
    return 0
  fi

  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  if ! repo_exists_for_owner "${GITEA_REPO_OWNER_FALLBACK}"; then
    return 0
  fi

  local payload code
  payload=$(cat <<EOF
{"new_owner":"${GITEA_REPO_OWNER}"}
EOF
)

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER_FALLBACK}/${GITEA_REPO_NAME}/transfer" || echo 000)

  if [[ "${code}" != "202" && "${code}" != "201" && "${code}" != "409" ]]; then
    fail "Transfer repo returned HTTP $code"
  fi
}

create_repo_if_missing() {
  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  ensure_org_exists

  transfer_repo_if_needed
  if repo_exists_for_owner "${GITEA_REPO_OWNER}"; then
    return 0
  fi

  local payload code
  payload=$(cat <<EOF
{"name":"${GITEA_REPO_NAME}","private":true,"auto_init":false,"default_branch":"main"}
EOF
)

  local create_url
  if is_true "${GITEA_REPO_OWNER_IS_ORG}"; then
    create_url="${GITEA_HTTP_BASE}/api/v1/orgs/${GITEA_REPO_OWNER}/repos"
  else
    create_url="${GITEA_HTTP_BASE}/api/v1/user/repos"
  fi

  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${create_url}" || echo 000)

  if [[ "$code" != "201" && "$code" != "409" ]]; then
    fail "Create repo returned HTTP $code"
  fi
}

deploy_keys_url() {
  printf '%s/api/v1/repos/%s/%s/keys' "${GITEA_HTTP_BASE}" "${GITEA_REPO_OWNER}" "${GITEA_REPO_NAME}"
}

deploy_public_key_identity() {
  local key_type key_body rest
  read -r key_type key_body rest <<<"${DEPLOY_PUBLIC_KEY}"
  [[ -n "${key_type}" && -n "${key_body}" ]] || return 1
  printf '%s %s\n' "${key_type}" "${key_body}"
}

list_repo_deploy_keys() {
  curl -fsS \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    "$(deploy_keys_url)"
}

repo_has_current_deploy_key() {
  local keys_json="$1"
  local key_identity
  key_identity="$(deploy_public_key_identity)" || fail "DEPLOY_PUBLIC_KEY is not a valid SSH public key"

  jq -e --arg title "${DEPLOY_KEY_TITLE}" --arg key "${key_identity}" '
    [.[] | select(
      .title == $title
      and ((.key // "" | split(" ")[0:2] | join(" ")) == $key)
      and (.read_only == false)
    )] | length > 0
  ' <<<"${keys_json}" >/dev/null
}

repo_deploy_key_id_by_title() {
  local keys_json="$1"
  jq -er --arg title "${DEPLOY_KEY_TITLE}" '.[] | select(.title == $title) | .id' <<<"${keys_json}" | head -n 1
}

delete_repo_deploy_key() {
  local key_id="$1"
  local code
  code=$(curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -X DELETE \
    "$(deploy_keys_url)/${key_id}" || echo 000)

  if [[ "${code}" != "204" && "${code}" != "404" ]]; then
    fail "Delete stale deploy key returned HTTP ${code}"
  fi
}

post_repo_deploy_key() {
  local key_identity payload
  key_identity="$(deploy_public_key_identity)" || fail "DEPLOY_PUBLIC_KEY is not a valid SSH public key"
  payload=$(cat <<EOF
{"title":"${DEPLOY_KEY_TITLE}","key":"${key_identity}","read_only":false}
EOF
)

  curl -sS -o /dev/null -w "%{http_code}" \
    -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "$(deploy_keys_url)" || echo 000
}

ensure_deploy_key() {
  command -v jq >/dev/null 2>&1 || fail "jq not found"

  local code keys_json key_id attempt
  for attempt in 1 2 3 4 5; do
    code="$(post_repo_deploy_key)"

    if [[ "${code}" == "201" ]]; then
      return 0
    fi

    if [[ "${code}" != "422" && "${code}" != "409" ]]; then
      fail "Add deploy key returned HTTP ${code}"
    fi

    keys_json="$(list_repo_deploy_keys)" || fail "Add deploy key returned HTTP ${code}; could not list deploy keys"
    if repo_has_current_deploy_key "${keys_json}"; then
      return 0
    fi

    key_id="$(repo_deploy_key_id_by_title "${keys_json}" || true)"
    if [[ -n "${key_id}" ]]; then
      echo "Replacing stale Gitea deploy key '${DEPLOY_KEY_TITLE}' for ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}" >&2
      delete_repo_deploy_key "${key_id}"

      code="$(post_repo_deploy_key)"
      if [[ "${code}" == "201" ]]; then
        keys_json="$(list_repo_deploy_keys)" || fail "Could not list deploy keys after replacing stale key"
        repo_has_current_deploy_key "${keys_json}" && return 0
      fi
      if [[ "${code}" != "422" && "${code}" != "409" ]]; then
        fail "Add deploy key returned HTTP ${code} after replacing stale key"
      fi
    fi

    if [[ "${attempt}" == "5" ]]; then
      fail "Add deploy key returned HTTP ${code}, but the current key is not attached to ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}"
    fi

    echo "Gitea deploy key '${DEPLOY_KEY_TITLE}' was not attached after HTTP ${code}; retrying... (${attempt}/5)" >&2
    sleep 2
  done
}

render_policy_repo_tree() {
  local root_dir="$1"
  local repo_dir="${root_dir}/repo"
  local vendor_root="${repo_dir}/apps/vendor/charts"

  mkdir -p "${repo_dir}"
  cp -R "${STACK_DIR}/apps" "${repo_dir}/apps"
  cp -R "${STACK_DIR}/cluster-policies" "${repo_dir}/cluster-policies"
  render_image_signing_policy "${repo_dir}/cluster-policies/kyverno/shared"
  rewrite_public_hostnames "${repo_dir}"
  render_platform_gateway_proxy_config "${repo_dir}"
  apply_external_workload_images "${repo_dir}/apps/apim/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/mcp/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/workloads/base/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/dev/all.yaml"
  apply_external_workload_images "${repo_dir}/apps/uat/all.yaml"
  apply_external_platform_images "${repo_dir}"
  if ! is_true "${ENABLE_BACKSTAGE}"; then
    remove_backstage_idp_resources "${repo_dir}/apps/idp/all.yaml"
  fi
  configure_subnetcalc_direct_api "${repo_dir}"
  configure_progressive_delivery "${repo_dir}"
  render_grafana_application_manifest "${repo_dir}/apps/argocd-apps/95-grafana.application.yaml"
  render_prometheus_application_manifest "${repo_dir}/apps/argocd-apps/90-prometheus.application.yaml"
  rewrite_image_owner "${repo_dir}/apps/apim/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/mcp/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/auth-chat/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/chatgpt-sim/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/langfuse-demos/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/workloads/base/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/dev/all.yaml"
  rewrite_image_owner "${repo_dir}/apps/uat/all.yaml"
  prune_argocd_app_manifests "${repo_dir}/apps/argocd-apps"
  mkdir -p "${vendor_root}"
  rewrite_external_argocd_apps_to_vendored_charts "${repo_dir}/apps/argocd-apps" "${vendor_root}"
  vendor_direct_tf_only_charts "${vendor_root}"
  if [[ -d "${repo_dir}/apps/platform-gateway-routes" ]]; then
    prune_gateway_routes_manifests "${repo_dir}/apps/platform-gateway-routes"
    render_gateway_route_admin_allowlist "${repo_dir}/apps/platform-gateway-routes"
    render_gateway_route_forwarded_headers "${repo_dir}/apps/platform-gateway-routes"
  fi
  if [[ -d "${repo_dir}/apps/platform-gateway-routes-sso" ]]; then
    prune_gateway_routes_manifests "${repo_dir}/apps/platform-gateway-routes-sso"
    render_gateway_route_admin_allowlist "${repo_dir}/apps/platform-gateway-routes-sso"
    render_gateway_route_forwarded_headers "${repo_dir}/apps/platform-gateway-routes-sso"
  fi
  rewrite_hardened_registry "${repo_dir}"

  printf '%s\n' "${repo_dir}"
}

render_repo() {
  render_policy_repo_tree "$@"
}

clone_remote_repo() {
  local dest="$1"
  local remote_url ssh_cmd

  for i in {1..20}; do
    refresh_gitea_git_access
    remote_url="ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"
    ssh_cmd="$(gitea_git_ssh_command)"

    rm -rf "${dest}"
    if GIT_SSH_COMMAND="$ssh_cmd" git clone -q --depth 1 --branch main "${remote_url}" "${dest}"; then
      return 0
    fi
    if GIT_SSH_COMMAND="$ssh_cmd" git clone -q --depth 1 "${remote_url}" "${dest}"; then
      return 0
    fi
    echo "git clone failed, retrying... ($i/20)" >&2
    sleep 3
  done

  return 1
}

show_dry_run_diff() {
  local rendered_dir="$1"
  local remote_dir
  local changes=""

  remote_dir="$(dirname "${rendered_dir}")/remote"
  if ! clone_remote_repo "${remote_dir}"; then
    fail "could not clone remote repo for dry-run"
  fi

  rsync -a --delete --exclude=.git "${rendered_dir}/" "${remote_dir}/"
  changes="$(git -C "${remote_dir}" status --short --untracked-files=all)"

  if [[ -z "${changes// }" ]]; then
    echo "No diff after sync for policies; nothing to push."
    return 0
  fi

  echo "==> [dry-run] Would commit with message: sync(policies): $(date -Iseconds)"
  printf '%s\n' "${changes}"
}

push_rendered_repo() {
  local rendered_dir="$1"

  pushd "${rendered_dir}" >/dev/null
  git init -q
  git config user.email "kind-demo@local"
  git config user.name "kind-demo"
  # Avoid failures when the host has global commit signing enabled (e.g. 1Password integration).
  git config commit.gpgsign false
  git add -A

  if git diff --cached --quiet; then
    # Ensure we still push at least once on fresh repos.
    echo "(no changes to commit; still ensuring remote is populated)" >&2
    git commit -q --allow-empty -m "sync policies"
  else
    git commit -q -m "sync policies"
  fi

  git branch -M main

  local pushed="false"
  for i in {1..20}; do
    local remote_url ssh_cmd
    refresh_gitea_git_access
    remote_url="ssh://${GITEA_SSH_USERNAME}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_REPO_OWNER}/${GITEA_REPO_NAME}.git"
    ssh_cmd="$(gitea_git_ssh_command)"
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "${remote_url}"
    else
      git remote add origin "${remote_url}"
    fi
    if GIT_SSH_COMMAND="$ssh_cmd" git push -q --force origin main; then
      pushed="true"
      break
    fi
    echo "git push failed, retrying... ($i/20)" >&2
    sleep 3
  done

  popd >/dev/null
  if [[ "$pushed" != "true" ]]; then
    echo "git push failed after retries" >&2
    return 1
  fi

  return 0
}

main() {
  local rendered_dir=""

  parse_args "$@"
  require_gitea_runtime_env
  load_gitea_local_access
  gitea_local_access_setup both
  : "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required after local access setup}"
  : "${GITEA_SSH_HOST:?GITEA_SSH_HOST is required after local access setup}"
  : "${GITEA_SSH_PORT:?GITEA_SSH_PORT is required after local access setup}"
  wait_for_gitea
  create_repo_if_missing
  ensure_deploy_key

  cleanup_tmp || true
  tmp="$(mktemp -d)"
  rendered_dir="$(render_repo "${tmp}")"

  if ! push_rendered_repo "${rendered_dir}"; then
    fail "git push failed"
  fi

  echo "Synced ${GITEA_REPO_OWNER}/${GITEA_REPO_NAME} from ${STACK_DIR}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
