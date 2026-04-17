#!/usr/bin/env bash

DOCKER_LOCAL_REGISTRY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_LOCAL_REGISTRY_REPO_ROOT="${REPO_ROOT:-$(cd "${DOCKER_LOCAL_REGISTRY_LIB_DIR}/../.." && pwd)}"
# shellcheck source=/dev/null
source "${DOCKER_LOCAL_REGISTRY_REPO_ROOT}/scripts/lib/http-fetch.sh"

registry_require_tools() {
  command -v docker >/dev/null 2>&1 || { echo "${0##*/}: docker not found" >&2; exit 1; }
}

registry_assert_reachable() {
  local cache_host="$1"

  http_fetch -fsS "http://${cache_host}/v2/" >/dev/null 2>&1 || {
    echo "${0##*/}: local cache not reachable at http://${cache_host}/v2/" >&2
    exit 1
  }
}

registry_cache_repo_and_tag() {
  local image_ref="$1"
  local ref_without_digest="${image_ref%%@*}"
  local ref_without_tag="${ref_without_digest}"
  local repo_path=""
  local tag="latest"
  local first_component=""

  if [[ "${ref_without_digest##*/}" == *:* ]]; then
    tag="${ref_without_digest##*:}"
    ref_without_tag="${ref_without_digest%:*}"
  fi

  if [[ "${ref_without_tag}" != */* ]]; then
    repo_path="library/${ref_without_tag}"
  else
    first_component="${ref_without_tag%%/*}"
    if [[ "${first_component}" == *.* || "${first_component}" == *:* || "${first_component}" == "localhost" ]]; then
      repo_path="${ref_without_tag#*/}"
    else
      repo_path="${ref_without_tag}"
    fi
  fi

  printf '%s\t%s\n' "${repo_path}" "${tag}"
}

registry_tag_list() {
  local cache_host="$1"
  local repo="$2"
  local payload=""

  payload="$(http_fetch -fsS "http://${cache_host}/v2/${repo}/tags/list" 2>/dev/null || true)"
  [ -n "${payload}" ] || return 1

  jq -r '.tags[]? // empty' <<<"${payload}" 2>/dev/null || true
}

registry_tag_exists() {
  local cache_host="$1"
  local repo="$2"
  local tag="$3"

  registry_tag_list "${cache_host}" "${repo}" | grep -Fx "${tag}" >/dev/null 2>&1
}

docker_push_local_registry() {
  local target_ref="$1"
  local push_ref="${target_ref}"
  local registry_host=""
  local docker_config_dir=""
  local docker_config_file=""
  local docker_config_tmp=""
  local rc=0

  if [ "${PLATFORM_DEVCONTAINER:-0}" = "1" ]; then
    local devcontainer_host_alias="${PLATFORM_DEVCONTAINER_HOST_ALIAS:-host.docker.internal}"

    if [[ "${push_ref}" == "${devcontainer_host_alias}:"* ]]; then
      # The devcontainer shell can reach the host via host.docker.internal,
      # but the Docker daemon pushes this local registry more reliably via
      # loopback. Keep the image refs stable and rewrite only the push target.
      push_ref="127.0.0.1${push_ref#${devcontainer_host_alias}}"
    fi
  fi

  if [ "${push_ref}" != "${target_ref}" ] && ! docker image inspect "${push_ref}" >/dev/null 2>&1; then
    if ! docker image inspect "${target_ref}" >/dev/null 2>&1; then
      echo "docker-local-registry: source image not found for push: ${target_ref}" >&2
      return 1
    fi
    docker tag "${target_ref}" "${push_ref}"
  fi

  registry_host="${push_ref%%/*}"

  docker_config_dir="$(mktemp -d)"
  if [[ -d "${HOME}/.docker" ]]; then
    cp -R "${HOME}/.docker/." "${docker_config_dir}/" 2>/dev/null || true
  fi
  docker_config_file="${docker_config_dir}/config.json"

  if command -v jq >/dev/null 2>&1 && [[ -f "${docker_config_file}" ]]; then
    docker_config_tmp="${docker_config_file}.tmp"
    jq --arg registry_host "${registry_host}" '
      del(.credsStore, .credHelpers) |
      .auths = (.auths // {}) |
      .auths[$registry_host] = (.auths[$registry_host] // {})
    ' "${docker_config_file}" > "${docker_config_tmp}"
    mv "${docker_config_tmp}" "${docker_config_file}"
  else
    printf '{ "auths": { "%s": {} } }\n' "${registry_host}" > "${docker_config_file}"
  fi

  if docker --config "${docker_config_dir}" push "${push_ref}" >/dev/null; then
    rc=0
  else
    rc=$?
  fi

  rm -rf "${docker_config_dir}"
  return "${rc}"
}
