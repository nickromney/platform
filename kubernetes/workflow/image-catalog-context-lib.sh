#!/usr/bin/env bash

IMAGE_CATALOG_TEMP_PATHS=()

image_catalog_context_root() {
  printf '%s\n' "${IMAGE_CATALOG_BUILD_CONTEXT_ROOT:-${PLUGIN_BUILD_CONTEXT_ROOT:-${REPO_ROOT}/.run/kind/build-contexts}}"
}

image_catalog_register_temp_path() {
  local path="${1:-}"

  [ -n "${path}" ] || return 0
  IMAGE_CATALOG_TEMP_PATHS+=("${path}")
}

image_catalog_cleanup_temp_paths() {
  local idx path

  if [ "${#IMAGE_CATALOG_TEMP_PATHS[@]}" -eq 0 ]; then
    return 0
  fi

  for ((idx=${#IMAGE_CATALOG_TEMP_PATHS[@]} - 1; idx >= 0; idx--)); do
    path="${IMAGE_CATALOG_TEMP_PATHS[idx]}"
    [ -n "${path}" ] || continue
    if [ -e "${path}" ]; then
      rm -rf "${path}"
    fi
  done
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

copy_backstage_source_tree() {
  local context_dir="$1"
  local source_dir="${REPO_ROOT}/apps/backstage"
  local root_file=""

  for root_file in \
    ".dockerignore" \
    ".yarnrc.yml" \
    "Dockerfile" \
    "README.md" \
    "app-config.production.yaml" \
    "app-config.yaml" \
    "backstage.json" \
    "catalog-info.yaml" \
    "package.json" \
    "tsconfig.json" \
    "yarn.lock"; do
    cp "${source_dir}/${root_file}" "${context_dir}/${root_file}"
  done

  mkdir -p "${context_dir}/.yarn"
  cp -R "${source_dir}/.yarn/releases" "${context_dir}/.yarn/releases"
  cp -R "${source_dir}/catalog" "${context_dir}/catalog"
  cp -R "${source_dir}/packages" "${context_dir}/packages"
  cp -R "${source_dir}/plugins" "${context_dir}/plugins"
}

image_catalog_prepare_backstage_build_context() {
  local __resultvar="$1"
  local context_dir=""
  local context_root=""

  context_root="$(image_catalog_context_root)"
  mkdir -p "${context_root}"
  context_dir="$(mktemp -d "${context_root}/backstage.XXXXXX")"
  image_catalog_register_temp_path "${context_dir}"
  [ -d "${REPO_ROOT}/apps/backstage" ] || { echo "${0##*/}: missing Backstage source directory" >&2; exit 1; }
  copy_backstage_source_tree "${context_dir}"
  copy_backstage_app_catalog "${context_dir}" "subnetcalc"
  copy_backstage_apim_simulator_catalog "${context_dir}"
  copy_backstage_app_catalog "${context_dir}" "sentiment"
  printf -v "${__resultvar}" '%s' "${context_dir}"
}

image_catalog_prepare_build_context_adapter() {
  local __resultvar="$1"
  local category="$2"
  local image_id="$3"
  local context_name="$4"
  local prepared_context_dir=""

  case "${category}:${image_id}:${context_name}" in
    "platform:backstage:generated-backstage")
      image_catalog_prepare_backstage_build_context prepared_context_dir
      printf -v "${__resultvar}" '%s' "${prepared_context_dir}"
      return 0
      ;;
  esac

  return 1
}
