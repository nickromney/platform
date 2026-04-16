#!/usr/bin/env bash

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
