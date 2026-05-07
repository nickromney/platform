#!/usr/bin/env bash

IMAGE_CATALOG_FILE="${IMAGE_CATALOG_FILE:-${REPO_ROOT}/kubernetes/workflow/image-catalog.json}"

image_catalog_require() {
  command -v jq >/dev/null 2>&1 || { echo "${0##*/}: jq not found" >&2; exit 1; }
  [ -f "${IMAGE_CATALOG_FILE}" ] || { echo "${0##*/}: image catalog not found: ${IMAGE_CATALOG_FILE}" >&2; exit 1; }
}

image_catalog_namespace() {
  image_catalog_require
  jq -r '.namespace' "${IMAGE_CATALOG_FILE}"
}

image_catalog_sources() {
  local category="$1"
  local image_id="$2"

  image_catalog_require
  jq -r --arg id "${image_id}" ".${category}_images[] | select(.id == \$id) | .fingerprint_sources[]?" "${IMAGE_CATALOG_FILE}"
}

image_catalog_source_tag() {
  local category="$1"
  local image_id="$2"
  local sources=()
  local source=""

  while IFS= read -r source; do
    [ -n "${source}" ] || continue
    sources+=("${source}")
  done < <(image_catalog_sources "${category}" "${image_id}")

  if [ "${#sources[@]}" -eq 0 ]; then
    return 0
  fi

  source_fingerprint_tag "${sources[@]}"
}

image_catalog_hcl_refs() {
  local category="$1"
  local cache_host="$2"
  local namespace="$3"
  shift 3

  local tag_overrides=("$@")
  local image_id=""
  local hcl_key=""
  local image_name=""
  local default_tag=""
  local tag=""
  local override=""
  local rendered_key=""

  image_catalog_require
  jq -r ".${category}_images[] | select(.external_ref != false) | [.id, .hcl_key, .image_name, .default_tag] | @tsv" "${IMAGE_CATALOG_FILE}" |
    while IFS=$'\t' read -r image_id hcl_key image_name default_tag; do
      tag="${default_tag:-latest}"
      for override in "${tag_overrides[@]}"; do
        if [ "${override%%=*}" = "${image_id}" ]; then
          tag="${override#*=}"
        fi
      done
      rendered_key="${hcl_key}"
      if [ "${hcl_key}" = "idp-core" ]; then
        rendered_key="\"${hcl_key}\""
      fi
      printf '  %-36s = %s\n' "${rendered_key}" "$(quote_hcl "${cache_host}/${namespace}/${image_name}:${tag}")"
    done
}
