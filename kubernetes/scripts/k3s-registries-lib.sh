#!/usr/bin/env bash

k3s_registry_for_image_ref() {
  local ref="${1%%@*}"
  local first

  if [[ "${ref}" != */* ]]; then
    echo "docker.io"
    return 0
  fi

  first="${ref%%/*}"
  if [[ "${first}" == *.* || "${first}" == *:* || "${first}" == "localhost" ]]; then
    echo "${first}"
  else
    echo "docker.io"
  fi
}

k3s_registry_default_endpoint() {
  case "$1" in
    docker.io)
      echo "https://registry-1.docker.io"
      ;;
    *)
      echo "https://$1"
      ;;
  esac
}

k3s_registry_append_mirror_entry() {
  local mirror_name="$1"
  shift

  if [[ "${K3S_REGISTRIES_PAYLOAD}" != mirrors:* ]]; then
    K3S_REGISTRIES_PAYLOAD+="mirrors:\n"
  fi

  K3S_REGISTRIES_PAYLOAD+="  \"${mirror_name}\":\n"
  K3S_REGISTRIES_PAYLOAD+="    endpoint:\n"
  while [[ $# -gt 0 ]]; do
    K3S_REGISTRIES_PAYLOAD+="      - \"$1\"\n"
    shift
  done
}

k3s_registry_image_list_registries() {
  local image_list_file="$1"
  local image

  [ -n "${image_list_file}" ] || return 0
  [ -f "${image_list_file}" ] || return 0

  while IFS= read -r image; do
    [[ -z "${image}" || "${image}" =~ ^# ]] && continue
    k3s_registry_for_image_ref "${image}"
  done < "${image_list_file}" | awk 'NF { print }' | sort -u
}

k3s_registries_render() {
  local image_list_file=""
  local cache_host=""
  local cache_scheme="http"
  local gitea_host=""
  local gitea_scheme="http"
  local registry=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image-list)
        image_list_file="$2"
        shift 2
        ;;
      --cache-host)
        cache_host="$2"
        shift 2
        ;;
      --cache-scheme)
        cache_scheme="$2"
        shift 2
        ;;
      --gitea-host)
        gitea_host="$2"
        shift 2
        ;;
      --gitea-scheme)
        gitea_scheme="$2"
        shift 2
        ;;
      *)
        echo "ERROR: unknown k3s registries renderer argument: $1" >&2
        return 2
        ;;
    esac
  done

  K3S_REGISTRIES_PAYLOAD=""

  if [[ -n "${cache_host}" ]]; then
    k3s_registry_append_mirror_entry "${cache_host}" "${cache_scheme}://${cache_host}"
    while IFS= read -r registry; do
      [[ -n "${registry}" ]] || continue
      k3s_registry_append_mirror_entry \
        "${registry}" \
        "${cache_scheme}://${cache_host}" \
        "$(k3s_registry_default_endpoint "${registry}")"
    done < <(k3s_registry_image_list_registries "${image_list_file}")
  fi

  if [[ -n "${gitea_host}" ]]; then
    k3s_registry_append_mirror_entry "${gitea_host}" "${gitea_scheme}://${gitea_host}"
  fi

  [ -n "${K3S_REGISTRIES_PAYLOAD}" ] || return 0
  printf '%b' "${K3S_REGISTRIES_PAYLOAD}"
}
