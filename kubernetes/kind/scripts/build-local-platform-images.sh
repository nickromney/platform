#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/local-cache-lib.sh"
export VARIABLES_FILE="${VARIABLES_FILE:-${REPO_ROOT}/terraform/kubernetes/variables.tf}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh"

CACHE_PUSH_HOST="${CACHE_PUSH_HOST:-127.0.0.1:5002}"
CACHE_BUILD_HOST="${CACHE_BUILD_HOST:-${CACHE_PUSH_HOST}}"
BASE_IMAGE_NAMESPACE="${BASE_IMAGE_NAMESPACE:-platform-cache}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-platform}"
TAG="${TAG:-latest}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
ENABLE_BACKSTAGE="${ENABLE_BACKSTAGE:-true}"
GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-12.3.1}"
GRAFANA_BASE_IMAGE_SOURCE="${GRAFANA_BASE_IMAGE_SOURCE:-docker.io/grafana/grafana:${GRAFANA_IMAGE_TAG}}"
PLUGIN_FETCH_IMAGE_SOURCE="${PLUGIN_FETCH_IMAGE_SOURCE:-docker.io/library/alpine:3.22}"
VICTORIA_LOGS_PLUGIN_VERSION="${VICTORIA_LOGS_PLUGIN_VERSION:-$(tf_default_from_variables grafana_victoria_logs_plugin_version)}"
VICTORIA_LOGS_PLUGIN_SHA256="${VICTORIA_LOGS_PLUGIN_SHA256:-$(tf_default_from_variables grafana_victoria_logs_plugin_sha256)}"
VICTORIA_LOGS_PLUGIN_URL="${VICTORIA_LOGS_PLUGIN_URL:-https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/v${VICTORIA_LOGS_PLUGIN_VERSION}/victoriametrics-logs-datasource-v${VICTORIA_LOGS_PLUGIN_VERSION}.zip}"
PLUGIN_ARCHIVE_CACHE_DIR="${PLUGIN_ARCHIVE_CACHE_DIR:-${REPO_ROOT}/.run/kind/plugin-cache}"
PLUGIN_BUILD_CONTEXT_ROOT="${PLUGIN_BUILD_CONTEXT_ROOT:-${REPO_ROOT}/.run/kind/build-contexts}"
TEMP_PATHS=()

register_temp_path() {
  local path="${1:-}"

  [ -n "${path}" ] || return 0
  TEMP_PATHS+=("${path}")
}

cleanup_temp_paths() {
  local idx path

  if [ "${#TEMP_PATHS[@]}" -eq 0 ]; then
    return 0
  fi

  for ((idx=${#TEMP_PATHS[@]} - 1; idx >= 0; idx--)); do
    path="${TEMP_PATHS[idx]}"
    [ -n "${path}" ] || continue
    if [ -e "${path}" ]; then
      rm -rf "${path}"
    fi
  done
}

trap cleanup_temp_paths EXIT

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
command -v shasum >/dev/null 2>&1 || { echo "${0##*/}: shasum not found" >&2; exit 1; }
[ -n "${VICTORIA_LOGS_PLUGIN_VERSION}" ] || { echo "${0##*/}: grafana_victoria_logs_plugin_version is empty" >&2; exit 1; }
[ -n "${VICTORIA_LOGS_PLUGIN_SHA256}" ] || { echo "${0##*/}: grafana_victoria_logs_plugin_sha256 is empty" >&2; exit 1; }

commit_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true)"

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
  register_temp_path "${tmp_path}"
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
  register_temp_path "${context_dir}"
  cp "${REPO_ROOT}/kubernetes/kind/images/grafana-victorialogs/Dockerfile" "${context_dir}/Dockerfile"
  cp "${archive_path}" "${context_dir}/victorialogs.zip"
  printf -v "${__resultvar}" '%s' "${context_dir}"
}

copy_backstage_app_catalog() {
  local context_dir="$1"
  local app_name="$2"
  local app_dir="${REPO_ROOT}/apps/${app_name}"
  local target_dir="${context_dir}/catalog/apps/${app_name}"

  mkdir -p "${target_dir}"
  cp "${app_dir}/catalog-info.yaml" "${target_dir}/catalog-info.yaml"
  cp "${app_dir}/mkdocs.yml" "${target_dir}/mkdocs.yml"
  cp "${app_dir}/README.md" "${target_dir}/README.md"
  if [ -d "${app_dir}/docs" ]; then
    cp -R "${app_dir}/docs" "${target_dir}/docs"
  fi
  if [ -f "${app_dir}/MODEL_CARD.md" ]; then
    cp "${app_dir}/MODEL_CARD.md" "${target_dir}/MODEL_CARD.md"
  fi
}

copy_backstage_apim_simulator_catalog() {
  local context_dir="$1"
  local source_file="${REPO_ROOT}/apps/apim-simulator/catalog-info.yaml"
  local target_dir="${context_dir}/catalog/apps/apim-simulator"

  mkdir -p "${target_dir}"
  cp "${source_file}" "${target_dir}/catalog-info.yaml"
}

prepare_backstage_build_context() {
  local __resultvar="$1"
  local context_dir=""

  mkdir -p "${PLUGIN_BUILD_CONTEXT_ROOT}"
  context_dir="$(mktemp -d "${PLUGIN_BUILD_CONTEXT_ROOT}/backstage.XXXXXX")"
  register_temp_path "${context_dir}"
  [ -d "${REPO_ROOT}/apps/backstage" ] || { echo "${0##*/}: missing Backstage source directory" >&2; exit 1; }
  cp -R "${REPO_ROOT}/apps/backstage/." "${context_dir}/"
  cp "${REPO_ROOT}/apps/backstage/Dockerfile" "${context_dir}/Dockerfile"
  copy_backstage_app_catalog "${context_dir}" "subnetcalc"
  copy_backstage_apim_simulator_catalog "${context_dir}"
  copy_backstage_app_catalog "${context_dir}" "sentiment"
  printf -v "${__resultvar}" '%s' "${context_dir}"
}

build_and_push() {
  local image_name="$1"
  local build_context="$2"
  local dockerfile_path="$3"
  local version_tag="$4"
  local fingerprint_tag="$5"
  shift 5

  local repo="${IMAGE_NAMESPACE}/${image_name}"
  local build_ref="build-${image_name}:${version_tag}"
  local latest_ref="${CACHE_PUSH_HOST}/${repo}:${TAG}"
  local version_ref="${CACHE_PUSH_HOST}/${repo}:${version_tag}"
  local commit_ref=""
  local fingerprint_ref=""
  local cmd=()

  if [ -n "${commit_tag}" ]; then
    commit_ref="${CACHE_PUSH_HOST}/${repo}:${commit_tag}"
  fi
  if [ -n "${fingerprint_tag}" ]; then
    fingerprint_ref="${CACHE_PUSH_HOST}/${repo}:${fingerprint_tag}"
  fi

  if [ "${FORCE_REBUILD}" != "1" ] \
    && tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${version_tag}" \
    && tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${TAG}" \
    && { [ -z "${fingerprint_tag}" ] || tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}"; }; then
    echo "OK   cached ${version_ref}"
    return 0
  fi

  echo "BUILD ${image_name}"
  # Build into a local staging tag first; the final registry push happens
  # explicitly below and should not be part of the build/export step.
  cmd=(-t "${build_ref}" -f "${dockerfile_path}")
  while [[ $# -gt 0 ]]; do
    cmd+=("$1")
    shift
  done
  cmd+=("${build_context}")
  docker_build_local "${cmd[@]}"

  docker tag "${build_ref}" "${version_ref}"
  docker tag "${build_ref}" "${latest_ref}"
  docker_push_local_registry "${version_ref}"
  docker_push_local_registry "${latest_ref}"

  if [ -n "${commit_ref}" ]; then
    docker tag "${build_ref}" "${commit_ref}"
    docker_push_local_registry "${commit_ref}"
  fi
  if [ -n "${fingerprint_ref}" ]; then
    docker tag "${build_ref}" "${fingerprint_ref}"
    docker_push_local_registry "${fingerprint_ref}"
  fi

  echo "PUSH  ${version_ref}"
}

source_fingerprint_tag() {
  local digest

  digest="$(
    cd "${REPO_ROOT}"
    find "$@" -type f -print |
      LC_ALL=C sort |
      while IFS= read -r source_file; do
        printf '%s\n' "${source_file}"
        shasum -a 256 "${source_file}"
      done |
      shasum -a 256 |
      awk '{print $1}'
  )"
  printf 'src-%s' "${digest:0:20}"
}

grafana_version_tag="${GRAFANA_IMAGE_TAG}-v${VICTORIA_LOGS_PLUGIN_VERSION}"
grafana_base_repo="${BASE_IMAGE_NAMESPACE}/grafana-grafana"
plugin_fetch_repo="${BASE_IMAGE_NAMESPACE}/library-alpine"
grafana_base_ref="${CACHE_BUILD_HOST}/${grafana_base_repo}:${GRAFANA_IMAGE_TAG}"
plugin_fetch_ref="${CACHE_BUILD_HOST}/${plugin_fetch_repo}:3.22"
grafana_plugin_archive=""
grafana_build_context=""
backstage_build_context=""

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
  "3.22" \
  "${FORCE_REBUILD}"

prepare_grafana_plugin_archive grafana_plugin_archive
prepare_grafana_build_context grafana_build_context "${grafana_plugin_archive}"

build_and_push \
  "grafana-victorialogs" \
  "${grafana_build_context}" \
  "${grafana_build_context}/Dockerfile" \
  "${grafana_version_tag}" \
  "" \
  --build-arg GRAFANA_BASE_IMAGE="${grafana_base_ref}" \
  --build-arg PLUGIN_FETCH_IMAGE="${plugin_fetch_ref}" \
  --build-arg GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG}"

idp_core_source_tag="$(
  source_fingerprint_tag \
    apps/idp-core/.dockerignore \
    apps/idp-core/Dockerfile \
    apps/idp-core/Dockerfile.dockerignore \
    apps/idp-core/app \
    apps/idp-core/pyproject.toml \
    apps/idp-core/uv.lock \
    catalog/platform-apps.json
)"
platform_mcp_source_tag="$(
  source_fingerprint_tag \
    apps/platform-mcp/.dockerignore \
    apps/platform-mcp/Dockerfile \
    apps/platform-mcp/Dockerfile.dockerignore \
    apps/platform-mcp/platform_mcp \
    apps/platform-mcp/pyproject.toml \
    apps/platform-mcp/uv.lock
)"
backstage_source_tag="$(
  if [ "${ENABLE_BACKSTAGE}" = "true" ]; then
    source_fingerprint_tag \
      apps/subnetcalc/catalog-info.yaml \
      apps/subnetcalc/docs \
      apps/subnetcalc/mkdocs.yml \
      apps/subnetcalc/README.md \
      apps/sentiment/catalog-info.yaml \
      apps/sentiment/docs \
      apps/sentiment/mkdocs.yml \
      apps/sentiment/MODEL_CARD.md \
      apps/sentiment/README.md \
      apps/backstage/.dockerignore \
      apps/backstage/.yarnrc.yml \
      apps/backstage/.yarn \
      apps/backstage/Dockerfile \
      apps/backstage/app-config.production.yaml \
      apps/backstage/app-config.yaml \
      apps/backstage/backstage.json \
      apps/backstage/catalog \
      apps/backstage/catalog-info.yaml \
      apps/backstage/package.json \
      apps/backstage/packages \
      apps/backstage/plugins \
      apps/backstage/tsconfig.json \
      apps/backstage/yarn.lock
  fi
)"
keycloak_source_tag="$(
  source_fingerprint_tag \
    apps/keycloak/.dockerignore \
    apps/keycloak/Dockerfile
)"

build_and_push \
  "idp-core" \
  "${REPO_ROOT}" \
  "${REPO_ROOT}/apps/idp-core/Dockerfile" \
  "${TAG}" \
  "${idp_core_source_tag}"

build_and_push \
  "platform-mcp" \
  "${REPO_ROOT}" \
  "${REPO_ROOT}/apps/platform-mcp/Dockerfile" \
  "${TAG}" \
  "${platform_mcp_source_tag}"

if [ "${ENABLE_BACKSTAGE}" = "true" ]; then
  prepare_backstage_build_context backstage_build_context
  build_and_push \
    "backstage" \
    "${backstage_build_context}" \
    "${backstage_build_context}/Dockerfile" \
    "${TAG}" \
    "${backstage_source_tag}"
else
  echo "SKIP backstage (ENABLE_BACKSTAGE=false)"
fi

build_and_push \
  "keycloak" \
  "${REPO_ROOT}/apps/keycloak" \
  "${REPO_ROOT}/apps/keycloak/Dockerfile" \
  "${TAG}" \
  "${keycloak_source_tag}"
