#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${STACK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
export VARIABLES_FILE="${STACK_DIR}/variables.tf"
DEFAULT_GITEA_SYNC_TFVARS_FILE="${REPO_ROOT}/kubernetes/kind/stages/900-sso.tfvars"
GITEA_SYNC_TFVARS_FILE="${GITEA_SYNC_TFVARS_FILE:-${DEFAULT_GITEA_SYNC_TFVARS_FILE}}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/platform-env.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/tf-defaults.sh"

usage() {
  cat <<EOF
Usage: sync-gitea.sh [--dry-run] [--execute]

Compatibility wrapper for manual policies syncs. This script resolves the
expected environment from stage tfvars, then delegates to sync-gitea-policies.sh
so manual syncs and Terraform-driven syncs render the same repository state.

$(shell_cli_standard_options)
EOF
}

tfvar_bool_or_default() {
  local key="$1"
  local default_value="$2"

  if [[ ! -f "${GITEA_SYNC_TFVARS_FILE}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  local value
  value="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(true|false).*/\\1/p" "${GITEA_SYNC_TFVARS_FILE}" | tail -n 1)"
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

tfvar_string_or_default() {
  local key="$1"
  local default_value="$2"

  if [[ ! -f "${GITEA_SYNC_TFVARS_FILE}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  local value
  value="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\\1/p" "${GITEA_SYNC_TFVARS_FILE}" | tail -n 1)"
  if [[ -z "${value}" ]]; then
    value="$(sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*([^#[:space:]]+).*/\\1/p" "${GITEA_SYNC_TFVARS_FILE}" | tail -n 1)"
  fi
  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

resolve_bool() {
  local env_name="$1"
  local tfvar_key="$2"
  local default_value="$3"
  local current="${!env_name:-}"

  if [[ -n "${current}" ]]; then
    printf '%s\n' "${current}"
    return 0
  fi

  tfvar_bool_or_default "${tfvar_key}" "${default_value}"
}

resolve_string() {
  local env_name="$1"
  local tfvar_key="$2"
  local default_value="$3"
  local current="${!env_name:-}"

  if [[ -n "${current}" ]]; then
    printf '%s\n' "${current}"
    return 0
  fi

  tfvar_string_or_default "${tfvar_key}" "${default_value}"
}

export_resolved_bool() {
  local env_name="$1"
  local tfvar_key="$2"
  local default_value="$3"
  local resolved_value=""

  resolved_value="$(resolve_bool "${env_name}" "${tfvar_key}" "${default_value}")"
  printf -v "${env_name}" '%s' "${resolved_value}"
  export "${env_name?}"
}

export_resolved_string() {
  local env_name="$1"
  local tfvar_key="$2"
  local default_value="$3"
  local resolved_value=""

  resolved_value="$(resolve_string "${env_name}" "${tfvar_key}" "${default_value}")"
  printf -v "${env_name}" '%s' "${resolved_value}"
  export "${env_name?}"
}

main() {
  shell_cli_handle_standard_no_args usage "would resolve Gitea sync inputs and delegate to sync-gitea-policies.sh" "$@"
  platform_load_env

  local delegate="${SCRIPT_DIR}/sync-gitea-policies.sh"
  [[ -x "${delegate}" ]] || { echo "sync-gitea.sh: missing ${delegate}" >&2; exit 1; }

  local gitea_http_port
  local gitea_admin_username
  local gitea_admin_pwd
  local gitea_ssh_username
  local gitea_local_access_mode
  local gitea_ssh_port
  local gitea_repo_owner
  local gitea_repo_owner_is_org
  local gitea_repo_owner_fallback
  local ssh_private_key_path
  local deploy_public_key

  gitea_http_port="$(resolve_string GITEA_HTTP_NODE_PORT gitea_http_node_port 30090)"
  gitea_admin_username="$(resolve_string GITEA_ADMIN_USERNAME gitea_admin_username gitea-admin)"
  gitea_admin_pwd="$(resolve_string GITEA_ADMIN_PWD gitea_admin_pwd "${PLATFORM_ADMIN_PASSWORD:-}")"
  gitea_ssh_username="$(resolve_string GITEA_SSH_USERNAME gitea_ssh_username git)"
  gitea_local_access_mode="$(resolve_string GITEA_LOCAL_ACCESS_MODE gitea_local_access_mode nodeport)"
  gitea_ssh_port="$(resolve_string GITEA_SSH_PORT gitea_ssh_node_port 30022)"
  gitea_repo_owner="$(resolve_string GITEA_REPO_OWNER gitea_repo_owner "")"
  gitea_repo_owner_is_org="$(resolve_bool GITEA_REPO_OWNER_IS_ORG gitea_repo_owner_is_org false)"

  if [[ -z "${gitea_admin_pwd}" ]]; then
    platform_require_vars PLATFORM_ADMIN_PASSWORD || exit 1
    gitea_admin_pwd="${PLATFORM_ADMIN_PASSWORD}"
  fi

  if [[ -z "${gitea_repo_owner}" ]]; then
    gitea_repo_owner="${gitea_admin_username}"
  fi

  if [[ -n "${GITEA_REPO_OWNER_FALLBACK:-}" ]]; then
    gitea_repo_owner_fallback="${GITEA_REPO_OWNER_FALLBACK}"
  elif [[ "${gitea_repo_owner_is_org}" == "true" ]]; then
    gitea_repo_owner_fallback="${gitea_admin_username}"
  else
    gitea_repo_owner_fallback=""
  fi

  ssh_private_key_path="${SSH_PRIVATE_KEY_PATH:-${STACK_DIR}/.run/policies-repo.id_ed25519}"
  [[ -f "${ssh_private_key_path}" ]] || {
    echo "sync-gitea.sh: missing SSH private key at ${ssh_private_key_path}" >&2
    exit 1
  }

  deploy_public_key="${DEPLOY_PUBLIC_KEY:-$(ssh-keygen -y -f "${ssh_private_key_path}" 2>/dev/null)}"
  [[ -n "${deploy_public_key}" ]] || {
    echo "sync-gitea.sh: could not derive public key from ${ssh_private_key_path}" >&2
    exit 1
  }

  export STACK_DIR
  export GITEA_LOCAL_ACCESS_MODE="${gitea_local_access_mode}"
  export GITEA_HTTP_NODE_PORT="${gitea_http_port}"
  export GITEA_HTTP_BASE="${GITEA_HTTP_BASE:-http://127.0.0.1:${gitea_http_port}}"
  export GITEA_ADMIN_USERNAME="${gitea_admin_username}"
  export GITEA_ADMIN_PWD="${gitea_admin_pwd}"
  export GITEA_SSH_USERNAME="${gitea_ssh_username}"
  export GITEA_SSH_NODE_PORT="${gitea_ssh_port}"
  export GITEA_SSH_HOST="${GITEA_SSH_HOST:-127.0.0.1}"
  export GITEA_SSH_PORT="${gitea_ssh_port}"
  export GITEA_REPO_OWNER="${gitea_repo_owner}"
  export GITEA_REPO_OWNER_IS_ORG="${gitea_repo_owner_is_org}"
  export GITEA_REPO_OWNER_FALLBACK="${gitea_repo_owner_fallback}"
  export GITEA_REPO_NAME="${GITEA_REPO_NAME:-policies}"
  export DEPLOY_KEY_TITLE="${DEPLOY_KEY_TITLE:-argocd-policies-repo-key}"
  export DEPLOY_PUBLIC_KEY="${deploy_public_key}"
  export SSH_PRIVATE_KEY_PATH="${ssh_private_key_path}"
  export_resolved_bool ENABLE_POLICIES enable_policies true
  export_resolved_bool ENABLE_GATEWAY_TLS enable_gateway_tls true
  export_resolved_bool ENABLE_CERT_MANAGER enable_cert_manager true
  export_resolved_bool ENABLE_ACTIONS_RUNNER enable_actions_runner true
  export_resolved_bool ENABLE_APP_REPO_SENTIMENT enable_app_repo_sentiment true
  export_resolved_bool ENABLE_APP_REPO_SUBNETCALC enable_app_repo_subnetcalc true
  export_resolved_bool ENABLE_PROMETHEUS enable_prometheus true
  export_resolved_bool ENABLE_GRAFANA enable_grafana true
  export_resolved_bool ENABLE_LOKI enable_loki false
  export_resolved_bool ENABLE_TEMPO enable_tempo false
  export_resolved_bool ENABLE_SIGNOZ enable_signoz false
  export_resolved_bool ENABLE_OTEL_GATEWAY enable_otel_gateway false
  export_resolved_bool ENABLE_OBSERVABILITY_AGENT enable_observability_agent false
  export_resolved_bool ENABLE_HEADLAMP enable_headlamp true
  export_resolved_string HARDENED_IMAGE_REGISTRY hardened_image_registry dhi.io
  export POLICIES_REPO_URL_CLUSTER="${POLICIES_REPO_URL_CLUSTER:-ssh://${gitea_ssh_username}@gitea-ssh.gitea.svc.cluster.local:22/${gitea_repo_owner}/${GITEA_REPO_NAME:-policies}.git}"
  export_resolved_string CERT_MANAGER_CHART_VERSION cert_manager_chart_version "$(tf_default_from_variables cert_manager_chart_version)"
  export_resolved_string DEX_CHART_VERSION dex_chart_version "$(tf_default_from_variables dex_chart_version)"
  export_resolved_string GRAFANA_CHART_VERSION grafana_chart_version "$(tf_default_from_variables grafana_chart_version)"
  export_resolved_string HEADLAMP_CHART_VERSION headlamp_chart_version "$(tf_default_from_variables headlamp_chart_version)"
  export_resolved_string KYVERNO_CHART_VERSION kyverno_chart_version "$(tf_default_from_variables kyverno_chart_version)"
  export_resolved_string LOKI_CHART_VERSION loki_chart_version "$(tf_default_from_variables loki_chart_version)"
  export_resolved_string OAUTH2_PROXY_CHART_VERSION oauth2_proxy_chart_version "$(tf_default_from_variables oauth2_proxy_chart_version)"
  export_resolved_string OPENTELEMETRY_COLLECTOR_CHART_VERSION opentelemetry_collector_chart_version "$(tf_default_from_variables opentelemetry_collector_chart_version)"
  export_resolved_string POLICY_REPORTER_CHART_VERSION policy_reporter_chart_version "$(tf_default_from_variables policy_reporter_chart_version)"
  export_resolved_string PROMETHEUS_CHART_VERSION prometheus_chart_version "$(tf_default_from_variables prometheus_chart_version)"
  export_resolved_string SIGNOZ_CHART_VERSION signoz_chart_version "$(tf_default_from_variables signoz_chart_version)"
  export_resolved_string TEMPO_CHART_VERSION tempo_chart_version "$(tf_default_from_variables tempo_chart_version)"

  exec "${delegate}" --execute
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
