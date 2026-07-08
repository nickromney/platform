#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/kubernetes/scripts/local-cache-lib.sh"
export VARIABLES_FILE="${VARIABLES_FILE:-${REPO_ROOT}/terraform/kubernetes/variables.tf}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/workflow/image-catalog-context-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/workflow/image-build-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/kubernetes/scripts/image-signing-lib.sh"

GRAFANA_CATALOG_BUILD_JSON="$(image_catalog_build_json platform grafana-victorialogs)"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_BUILD_JSON="$(image_catalog_build_json platform argo-rollouts-gatewayapi-plugin)"

catalog_grafana_build_value() {
  local filter="$1"

  jq -r "${filter} // empty" <<<"${GRAFANA_CATALOG_BUILD_JSON}"
}

catalog_grafana_image_ref() {
  local object_filter="$1"
  local source=""
  local tag=""

  source="$(catalog_grafana_build_value "${object_filter}.source")"
  tag="$(catalog_grafana_build_value "${object_filter}.tag")"
  [ -n "${source}" ] || { echo "${0##*/}: missing ${object_filter}.source in image catalog" >&2; exit 1; }
  [ -n "${tag}" ] || { echo "${0##*/}: missing ${object_filter}.tag in image catalog" >&2; exit 1; }
  printf '%s:%s\n' "${source}" "${tag}"
}

catalog_argo_rollouts_gatewayapi_plugin_build_value() {
  local filter="$1"

  jq -r "${filter} // empty" <<<"${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_BUILD_JSON}"
}

CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
CACHE_BUILD_HOST="${CACHE_BUILD_HOST:-${CACHE_PUSH_HOST}}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-platform}"
TAG="${TAG:-latest}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
ENABLE_BACKSTAGE="${ENABLE_BACKSTAGE:-true}"
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-$(catalog_grafana_build_value '.grafana_base_image.tag')}"
GRAFANA_BASE_IMAGE_SOURCE="${GRAFANA_BASE_IMAGE_SOURCE:-$(catalog_grafana_image_ref '.grafana_base_image')}"
GRAFANA_BASE_CACHE_REPO="${GRAFANA_BASE_CACHE_REPO:-$(catalog_grafana_build_value '.grafana_base_image.cache_repo')}"
PLUGIN_FETCH_IMAGE_SOURCE="${PLUGIN_FETCH_IMAGE_SOURCE:-$(catalog_grafana_image_ref '.plugin_fetch_image')}"
PLUGIN_FETCH_IMAGE_TAG="${PLUGIN_FETCH_IMAGE_TAG:-$(catalog_grafana_build_value '.plugin_fetch_image.tag')}"
PLUGIN_FETCH_CACHE_REPO="${PLUGIN_FETCH_CACHE_REPO:-$(catalog_grafana_build_value '.plugin_fetch_image.cache_repo')}"
VICTORIA_LOGS_PLUGIN_VERSION_VAR="$(catalog_grafana_build_value '.plugin_archive.terraform_version_variable')"
VICTORIA_LOGS_PLUGIN_SHA256_VAR="$(catalog_grafana_build_value '.plugin_archive.terraform_sha256_variable')"
VICTORIA_LOGS_PLUGIN_URL_TEMPLATE="$(catalog_grafana_build_value '.plugin_archive.url_template')"
VICTORIA_LOGS_PLUGIN_VERSION="${VICTORIA_LOGS_PLUGIN_VERSION:-$(tf_default_from_variables "${VICTORIA_LOGS_PLUGIN_VERSION_VAR}")}"
VICTORIA_LOGS_PLUGIN_SHA256="${VICTORIA_LOGS_PLUGIN_SHA256:-$(tf_default_from_variables "${VICTORIA_LOGS_PLUGIN_SHA256_VAR}")}"
VICTORIA_LOGS_PLUGIN_URL_DEFAULT="${VICTORIA_LOGS_PLUGIN_URL_TEMPLATE//\{version\}/${VICTORIA_LOGS_PLUGIN_VERSION}}"
VICTORIA_LOGS_PLUGIN_URL="${VICTORIA_LOGS_PLUGIN_URL:-${VICTORIA_LOGS_PLUGIN_URL_DEFAULT}}"
PLUGIN_ARCHIVE_CACHE_DIR="${PLUGIN_ARCHIVE_CACHE_DIR:-${REPO_ROOT}/$(catalog_grafana_build_value '.plugin_archive.cache_dir')}"
PLUGIN_CONTEXT_ARCHIVE_NAME="${PLUGIN_CONTEXT_ARCHIVE_NAME:-$(catalog_grafana_build_value '.plugin_archive.context_archive_name')}"
GRAFANA_VERSION_TAG_STRATEGY="$(catalog_grafana_build_value '.version_tag_strategy')"
PLUGIN_BUILD_CONTEXT_ROOT="${PLUGIN_BUILD_CONTEXT_ROOT:-${REPO_ROOT}/.run/kind/build-contexts}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION_VAR="$(catalog_argo_rollouts_gatewayapi_plugin_build_value '.plugin_binary.terraform_version_variable')"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256_VAR="$(catalog_argo_rollouts_gatewayapi_plugin_build_value '.plugin_binary.terraform_sha256_variable')"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL_TEMPLATE="$(catalog_argo_rollouts_gatewayapi_plugin_build_value '.plugin_binary.url_template')"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION:-$(tf_default_from_variables "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION_VAR}")}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256:-$(tf_default_from_variables "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256_VAR}")}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL_DEFAULT="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL_TEMPLATE//\{version\}/${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION}}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL:-${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL_DEFAULT}}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CACHE_DIR="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CACHE_DIR:-${REPO_ROOT}/$(catalog_argo_rollouts_gatewayapi_plugin_build_value '.plugin_binary.cache_dir')}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CONTEXT_BINARY_NAME="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CONTEXT_BINARY_NAME:-$(catalog_argo_rollouts_gatewayapi_plugin_build_value '.plugin_binary.context_binary_name')}"
ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION_TAG_STRATEGY="$(catalog_argo_rollouts_gatewayapi_plugin_build_value '.version_tag_strategy')"

trap image_catalog_cleanup_temp_paths EXIT

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Builds and pushes host-side platform images into the local registry cache for
kind-based workflows.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would build and push local platform images into ${CACHE_PUSH_HOST} with tag ${TAG}" "$@"

require_local_cache_tools
assert_local_cache_reachable "${CACHE_PUSH_HOST}"
image_signing_ensure_keypair
command -v shasum >/dev/null 2>&1 || { echo "${0##*/}: shasum not found" >&2; exit 1; }
[ -n "${VICTORIA_LOGS_PLUGIN_VERSION}" ] || { echo "${0##*/}: grafana_victoria_logs_plugin_version is empty" >&2; exit 1; }
[ -n "${VICTORIA_LOGS_PLUGIN_SHA256}" ] || { echo "${0##*/}: grafana_victoria_logs_plugin_sha256 is empty" >&2; exit 1; }
[ -n "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION}" ] || { echo "${0##*/}: argo_rollouts_gatewayapi_plugin_version is empty" >&2; exit 1; }
[[ "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "${0##*/}: argo_rollouts_gatewayapi_plugin_sha256 must be a lowercase 64-character SHA-256 hex digest" >&2
  exit 1
}

commit_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"
export IMAGE_BUILD_COMMIT_TAG="${commit_tag}"

prepare_grafana_plugin_archive() {
  local __resultvar="$1"
  local archive_name="victoriametrics-logs-datasource-v${VICTORIA_LOGS_PLUGIN_VERSION}.zip"
  local archive_path="${PLUGIN_ARCHIVE_CACHE_DIR}/${archive_name}"
  local tmp_path=""

  mkdir -p "${PLUGIN_ARCHIVE_CACHE_DIR}"

  if [ -f "${archive_path}" ] && printf '%s  %s\n' "${VICTORIA_LOGS_PLUGIN_SHA256}" "${archive_path}" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "OK   cached plugin ${archive_path}"
    printf -v "${__resultvar}" '%s' "${archive_path}"
    return 0
  fi

  tmp_path="$(mktemp "${PLUGIN_ARCHIVE_CACHE_DIR}/.${archive_name}.XXXXXX")"
  image_catalog_register_temp_path "${tmp_path}"
  echo "FETCH ${VICTORIA_LOGS_PLUGIN_URL} -> ${archive_path}"
  curl -fsSL "${VICTORIA_LOGS_PLUGIN_URL}" -o "${tmp_path}"
  printf '%s  %s\n' "${VICTORIA_LOGS_PLUGIN_SHA256}" "${tmp_path}" | shasum -a 256 -c - >/dev/null
  mv "${tmp_path}" "${archive_path}"
  echo "CACHE ${archive_path}"
  printf -v "${__resultvar}" '%s' "${archive_path}"
}

prepare_grafana_build_context() {
  local __resultvar="$1"
  local archive_path="$2"
  local context_dir=""

  mkdir -p "${PLUGIN_BUILD_CONTEXT_ROOT}"
  context_dir="$(mktemp -d "${PLUGIN_BUILD_CONTEXT_ROOT}/grafana-victorialogs.XXXXXX")"
  image_catalog_register_temp_path "${context_dir}"
  cp "${REPO_ROOT}/kubernetes/kind/images/grafana-victorialogs/Dockerfile" "${context_dir}/Dockerfile"
  cp "${archive_path}" "${context_dir}/${PLUGIN_CONTEXT_ARCHIVE_NAME:-victorialogs.zip}"
  printf -v "${__resultvar}" '%s' "${context_dir}"
}

prepare_argo_rollouts_gatewayapi_plugin_binary() {
  local __resultvar="$1"
  local binary_name="gatewayapi-plugin-linux-amd64-v${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION}"
  local binary_path="${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CACHE_DIR}/${binary_name}"
  local tmp_path=""

  mkdir -p "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CACHE_DIR}"

  if [ -f "${binary_path}" ] && printf '%s  %s\n' "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256}" "${binary_path}" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "OK   cached plugin ${binary_path}"
    printf -v "${__resultvar}" '%s' "${binary_path}"
    return 0
  fi

  tmp_path="$(mktemp "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CACHE_DIR}/.${binary_name}.XXXXXX")"
  image_catalog_register_temp_path "${tmp_path}"
  echo "FETCH ${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL} -> ${binary_path}"
  curl -fsSL "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_URL}" -o "${tmp_path}"
  printf '%s  %s\n' "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_SHA256}" "${tmp_path}" | shasum -a 256 -c - >/dev/null
  chmod 0755 "${tmp_path}"
  mv "${tmp_path}" "${binary_path}"
  echo "CACHE ${binary_path}"
  printf -v "${__resultvar}" '%s' "${binary_path}"
}

prepare_argo_rollouts_gatewayapi_plugin_build_context() {
  local __resultvar="$1"
  local binary_path="$2"
  local context_dir=""

  mkdir -p "${PLUGIN_BUILD_CONTEXT_ROOT}"
  context_dir="$(mktemp -d "${PLUGIN_BUILD_CONTEXT_ROOT}/argo-rollouts-gatewayapi-plugin.XXXXXX")"
  image_catalog_register_temp_path "${context_dir}"
  cp "${REPO_ROOT}/kubernetes/kind/images/argo-rollouts-gatewayapi-plugin/Dockerfile" "${context_dir}/Dockerfile"
  cp "${binary_path}" "${context_dir}/${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CONTEXT_BINARY_NAME:-gatewayapi-plugin-linux-amd64}"
  chmod 0755 "${context_dir}/${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_CONTEXT_BINARY_NAME:-gatewayapi-plugin-linux-amd64}"
  printf -v "${__resultvar}" '%s' "${context_dir}"
}

case "${GRAFANA_VERSION_TAG_STRATEGY}" in
  grafana-tag-plus-plugin-version)
    grafana_version_tag="${GRAFANA_IMAGE_TAG}-v${VICTORIA_LOGS_PLUGIN_VERSION}"
    ;;
  *)
    echo "${0##*/}: unsupported Grafana version_tag_strategy=${GRAFANA_VERSION_TAG_STRATEGY}" >&2
    exit 1
    ;;
esac

case "${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION_TAG_STRATEGY}" in
  plugin-version-with-v-prefix)
    argo_rollouts_gatewayapi_plugin_version_tag="v${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION}"
    ;;
  *)
    echo "${0##*/}: unsupported Argo Rollouts Gateway API plugin version_tag_strategy=${ARGO_ROLLOUTS_GATEWAYAPI_PLUGIN_VERSION_TAG_STRATEGY}" >&2
    exit 1
    ;;
esac

grafana_base_repo="${GRAFANA_BASE_CACHE_REPO}"
plugin_fetch_repo="${PLUGIN_FETCH_CACHE_REPO}"
grafana_base_ref="${CACHE_BUILD_HOST}/${grafana_base_repo}:${GRAFANA_IMAGE_TAG}"
plugin_fetch_ref="${CACHE_BUILD_HOST}/${plugin_fetch_repo}:${PLUGIN_FETCH_IMAGE_TAG}"
grafana_plugin_archive=""
grafana_build_context=""
argo_rollouts_gatewayapi_plugin_binary=""
argo_rollouts_gatewayapi_plugin_build_context=""

mirror_image_into_cache \
  "${GRAFANA_BASE_IMAGE_SOURCE}" \
  "${CACHE_PUSH_HOST}" \
  "${grafana_base_repo}" \
  "${GRAFANA_IMAGE_TAG}" \
  "${FORCE_REBUILD}"

mirror_image_into_cache \
  "${PLUGIN_FETCH_IMAGE_SOURCE}" \
  "${CACHE_PUSH_HOST}" \
  "${plugin_fetch_repo}" \
  "${PLUGIN_FETCH_IMAGE_TAG}" \
  "${FORCE_REBUILD}"

prepare_grafana_plugin_archive grafana_plugin_archive
prepare_grafana_build_context grafana_build_context "${grafana_plugin_archive}"

image_build_build_and_push_cached \
  "grafana-victorialogs" \
  "${grafana_build_context}" \
  "${grafana_build_context}/Dockerfile" \
  "${grafana_version_tag}" \
  "" \
  --build-arg GRAFANA_BASE_IMAGE="${grafana_base_ref}" \
  --build-arg PLUGIN_FETCH_IMAGE="${plugin_fetch_ref}" \
  --build-arg GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG}"

prepare_argo_rollouts_gatewayapi_plugin_binary argo_rollouts_gatewayapi_plugin_binary
prepare_argo_rollouts_gatewayapi_plugin_build_context argo_rollouts_gatewayapi_plugin_build_context "${argo_rollouts_gatewayapi_plugin_binary}"

image_build_build_and_push_cached \
  "argo-rollouts-gatewayapi-plugin" \
  "${argo_rollouts_gatewayapi_plugin_build_context}" \
  "${argo_rollouts_gatewayapi_plugin_build_context}/Dockerfile" \
  "${argo_rollouts_gatewayapi_plugin_version_tag}" \
  ""

idp_core_source_tag="$(
  image_catalog_source_tag platform idp-core
)"
platform_mcp_source_tag="$(
  image_catalog_source_tag platform platform-mcp
)"
auth_chat_source_tag="$(
  image_catalog_source_tag platform auth-chat
)"
chatgpt_sim_source_tag="$(
  image_catalog_source_tag platform chatgpt-sim
)"
langfuse_demos_source_tag="$(
  image_catalog_source_tag platform langfuse-demos
)"
backstage_source_tag="$(
  if [ "${ENABLE_BACKSTAGE}" = "true" ]; then
    image_catalog_source_tag platform backstage
  fi
)"
keycloak_source_tag="$(
  image_catalog_source_tag platform keycloak
)"

image_build_catalog_build_and_push platform idp-core idp-core "${idp_core_source_tag}"

image_build_catalog_build_and_push platform platform-mcp platform-mcp "${platform_mcp_source_tag}"

image_build_catalog_build_and_push platform auth-chat auth-chat "${auth_chat_source_tag}"

image_build_catalog_build_and_push platform chatgpt-sim chatgpt-sim "${chatgpt_sim_source_tag}"

image_build_catalog_build_and_push platform langfuse-demos langfuse-demos "${langfuse_demos_source_tag}"

if [ "${ENABLE_BACKSTAGE}" = "true" ]; then
  image_build_catalog_build_and_push platform backstage backstage "${backstage_source_tag}"
else
  echo "SKIP backstage (ENABLE_BACKSTAGE=false)"
fi

image_build_catalog_build_and_push platform keycloak keycloak "${keycloak_source_tag}"
