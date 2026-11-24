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

image_catalog_prepare_build_context_adapter() {
  # Extension point for an image whose build context must be assembled from
  # several source trees before docker build (args: result-var, category,
  # image id, context name). No platform image needs one now that the
  # Backstage image is gone, so every context falls through to image-build-lib.
  return 1
}
