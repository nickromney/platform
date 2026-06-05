#!/usr/bin/env bash

IMAGE_CATALOG_FILE="${IMAGE_CATALOG_FILE:-${REPO_ROOT}/kubernetes/workflow/image-catalog.json}"

image_catalog_require() {
  command -v jq >/dev/null 2>&1 || { echo "${0##*/}: jq not found" >&2; exit 1; }
  [ -f "${IMAGE_CATALOG_FILE}" ] || { echo "${0##*/}: image catalog not found: ${IMAGE_CATALOG_FILE}" >&2; exit 1; }
}

source_fingerprint_tag() {
  local digest

  digest="$(
    cd "${REPO_ROOT}" || exit 1
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

image_catalog_entry_exists() {
  local category="$1"
  local image_id="$2"

  image_catalog_require
  jq -e --arg id "${image_id}" ".${category}_images[]? | select(.id == \$id)" "${IMAGE_CATALOG_FILE}" >/dev/null
}

image_catalog_source_tag() {
  local category="$1"
  local image_id="$2"
  local sources=()
  local source=""

  if ! image_catalog_entry_exists "${category}" "${image_id}"; then
    echo "${0##*/}: ${category}.${image_id} not found in image catalog" >&2
    return 1
  fi

  while IFS= read -r source; do
    [ -n "${source}" ] || continue
    sources+=("${source}")
  done < <(image_catalog_sources "${category}" "${image_id}")

  if [ "${#sources[@]}" -eq 0 ]; then
    return 0
  fi

  for source in "${sources[@]}"; do
    if [ ! -e "${REPO_ROOT}/${source}" ] && [ ! -e "${source}" ]; then
      echo "${0##*/}: ${category}.${image_id} fingerprint source not found: ${source}" >&2
      return 1
    fi
  done

  source_fingerprint_tag "${sources[@]}"
}

image_catalog_external_ids() {
  local category="$1"

  image_catalog_require
  jq -r ".${category}_images[] | select(.external_ref != false) | .id" "${IMAGE_CATALOG_FILE}"
}

image_catalog_build_field() {
  local category="$1"
  local image_id="$2"
  local field="$3"

  image_catalog_require
  jq -r --arg id "${image_id}" --arg field "${field}" ".${category}_images[] | select(.id == \$id) | .build[\$field] // empty" "${IMAGE_CATALOG_FILE}"
}

image_catalog_build_json() {
  local category="$1"
  local image_id="$2"

  image_catalog_require
  jq -c --arg id "${image_id}" ".${category}_images[] | select(.id == \$id) | .build // {}" "${IMAGE_CATALOG_FILE}"
}

image_catalog_default_tag() {
  local category="$1"
  local image_id="$2"
  local tag=""

  image_catalog_require
  tag="$(jq -r --arg id "${image_id}" ".${category}_images[] | select(.id == \$id) | .default_tag // empty" "${IMAGE_CATALOG_FILE}")"
  [ -n "${tag}" ] || { echo "${0##*/}: ${category}.${image_id} is missing default_tag in image catalog" >&2; exit 1; }
  printf '%s\n' "${tag}"
}

image_catalog_build_specs() {
  local category="$1"
  local builder="$2"

  image_catalog_require
  jq -r \
    --arg category "${category}" \
    --arg builder "${builder}" \
    '.[$category + "_images"][]
      | select(.build != null)
      | select((.build.builder // $category) == $builder)
      | [.id, .image_name, .build.context, .build.dockerfile, (.build.tag // "default")]
      | @tsv' \
    "${IMAGE_CATALOG_FILE}"
}

image_catalog_build_arg_specs() {
  local category="$1"
  local image_id="$2"

  image_catalog_require
  jq -r \
    --arg category "${category}" \
    --arg id "${image_id}" \
    '.[$category + "_images"][]
      | select(.id == $id)
      | .build.args[]?
      | [.name, (.env // ""), (.default // "")]
      | @tsv' \
    "${IMAGE_CATALOG_FILE}"
}

image_catalog_version_check_projection() {
  image_catalog_require
  jq -r '
    (.platform_images[]
      | ["platform", .id, .hcl_key, .image_name, (.default_tag // ""), (.version_check.mode // "non-comparable"), (.version_check.reason // "")]
      | @tsv),
    (.workload_images[]
      | ["workload", .id, .hcl_key, .image_name, (.default_tag // ""), (.version_check.mode // "non-comparable"), (.version_check.reason // "")]
      | @tsv)
  ' "${IMAGE_CATALOG_FILE}"
}

image_catalog_preload_alignment_projection() {
  image_catalog_require
  jq -r '
    .preload_alignment_images[]?
    | [
        .id,
        .component,
        (.preload_alignment.kind // ""),
        (.preload_alignment.line_regex // ""),
        (.preload_alignment.tag_extract_sed // ""),
        (.preload_alignment.expected_source // ""),
        (.version_check.latest_lookup_policy // ""),
        (.version_check.checked_elsewhere // ""),
        (.version_check.preload_alignment_policy // ""),
        (.version_check.reason // ""),
        (.preload_alignment.enabled_by // "")
      ]
    | @tsv
  ' "${IMAGE_CATALOG_FILE}"
}

image_catalog_version_check_status_for_ref() {
  local image_ref="$1"

  image_catalog_require
  jq -r --arg ref "${image_ref}" '
    . as $catalog
    | ($catalog.variant_registry_hosts | to_entries[]?.value) as $host
    | (
        ($catalog.platform_images[] | {category: "platform", id: .id, image_name: .image_name, mode: (.version_check.mode // "non-comparable")}),
        ($catalog.workload_images[] | {category: "workload", id: .id, image_name: .image_name, mode: (.version_check.mode // "non-comparable")})
      )
    | . as $image
    | select($ref | startswith($host + "/" + $catalog.namespace + "/" + $image.image_name + ":"))
    | $image.mode
  ' "${IMAGE_CATALOG_FILE}" | head -n 1
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
  jq -r ".${category}_images[] | select(.external_ref != false) | [.id, .hcl_key, .image_name, (.default_tag // \"\")] | @tsv" "${IMAGE_CATALOG_FILE}" |
    while IFS=$'\t' read -r image_id hcl_key image_name default_tag; do
      [ -n "${default_tag}" ] || { echo "${0##*/}: ${category}.${image_id} is missing default_tag in image catalog" >&2; exit 1; }
      tag="${default_tag}"
      for override in "${tag_overrides[@]}"; do
        if [ "${override%%=*}" = "${image_id}" ]; then
          tag="${override#*=}"
        fi
      done
      rendered_key="${hcl_key}"
      if [[ "${hcl_key}" == *-* ]]; then
        rendered_key="\"${hcl_key}\""
      fi
      printf '  %-36s = %s\n' "${rendered_key}" "$(quote_hcl "${cache_host}/${namespace}/${image_name}:${tag}")"
    done
}
