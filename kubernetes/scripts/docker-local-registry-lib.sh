#!/usr/bin/env bash

docker_push_local_registry() {
  local target_ref="$1"
  local registry_host="${target_ref%%/*}"
  local docker_config_dir=""
  local docker_config_file=""
  local docker_config_tmp=""
  local rc=0

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

  if docker --config "${docker_config_dir}" push "${target_ref}" >/dev/null; then
    rc=0
  else
    rc=$?
  fi

  rm -rf "${docker_config_dir}"
  return "${rc}"
}
