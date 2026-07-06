#!/usr/bin/env bash

IMAGE_BUILD_ARGS=()
if [ -z "${IMAGE_BUILD_PREBUILD_COMMANDS_FILE:-}" ]; then
  IMAGE_BUILD_PREBUILD_COMMANDS_FILE="${TMPDIR:-/tmp}/image-build-prebuild-commands.$$"
  : >"${IMAGE_BUILD_PREBUILD_COMMANDS_FILE}"
  export IMAGE_BUILD_PREBUILD_COMMANDS_FILE
fi

image_build_commit_tag() {
  if [ -n "${IMAGE_BUILD_COMMIT_TAG:-}" ]; then
    printf '%s\n' "${IMAGE_BUILD_COMMIT_TAG}"
    return 0
  fi

  git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || true
}

image_build_tag_exists() {
  local cache_host="$1"
  local repo="$2"
  local tag="$3"

  if declare -F tag_exists_in_cache >/dev/null 2>&1; then
    tag_exists_in_cache "${cache_host}" "${repo}" "${tag}"
    return
  fi
  if declare -F registry_tag_exists >/dev/null 2>&1; then
    registry_tag_exists "${cache_host}" "${repo}" "${tag}"
    return
  fi

  echo "${0##*/}: no image cache tag-exists Adapter is available" >&2
  return 1
}

image_build_push_ref() {
  local target_ref="$1"

  if declare -F docker_push_local_registry >/dev/null 2>&1; then
    docker_push_local_registry "${target_ref}"
    return
  fi

  echo "${0##*/}: no image push Adapter is available" >&2
  return 1
}

image_build_run_docker() {
  if declare -F docker_build_local >/dev/null 2>&1; then
    docker_build_local "$@"
    return
  fi
  if declare -F docker_build >/dev/null 2>&1; then
    docker_build "$@"
    return
  fi
  if docker buildx version >/dev/null 2>&1; then
    docker buildx build --load --provenance=false "$@"
    return
  fi

  DOCKER_BUILDKIT=1 docker build "$@"
}

image_build_prepare_args() {
  local category="$1"
  local image_id="$2"
  local arg_name=""
  local env_name=""
  local default_value=""
  local arg_value=""

  IMAGE_BUILD_ARGS=()
  while IFS=$'\t' read -r arg_name env_name default_value; do
    [ -n "${arg_name}" ] || continue
    arg_value="${default_value:-}"
    if [ -n "${env_name}" ]; then
      arg_value="${!env_name-${arg_value}}"
    fi
    IMAGE_BUILD_ARGS+=(--build-arg "${arg_name}=${arg_value}")
  done < <(image_catalog_build_arg_specs "${category}" "${image_id}")
}

image_build_run_prebuild() {
  local category="$1"
  local image_id="$2"
  local command=""
  local cached_command=""

  command="$(image_catalog_build_field "${category}" "${image_id}" prebuild)"
  [ -n "${command}" ] || return 0

  echo "PREBUILD ${image_id}: ${command}"
  while IFS= read -r cached_command; do
    if [ "${cached_command}" = "${command}" ]; then
      return 0
    fi
  done <"${IMAGE_BUILD_PREBUILD_COMMANDS_FILE}"

  (cd "${REPO_ROOT}" && eval "${command}")
  printf '%s\n' "${command}" >>"${IMAGE_BUILD_PREBUILD_COMMANDS_FILE}"
}

image_build_resolve_context() {
  local category="$1"
  local image_id="$2"
  local context="$3"
  local context_dir=""

  case "${context}" in
    ".")
      printf '%s\n' "${REPO_ROOT}"
      ;;
    "")
      echo "${0##*/}: ${category}.${image_id} is missing build.context in image catalog" >&2
      exit 1
      ;;
    *)
      if declare -F image_catalog_prepare_build_context_adapter >/dev/null 2>&1 \
        && image_catalog_prepare_build_context_adapter context_dir "${category}" "${image_id}" "${context}"; then
        printf '%s\n' "${context_dir}"
        return 0
      fi
      if [[ "${context}" == generated-* ]]; then
        echo "${0##*/}: ${category}.${image_id} build.context=${context} has no context-preparation Adapter" >&2
        exit 1
      fi
      printf '%s/%s\n' "${REPO_ROOT}" "${context}"
      ;;
  esac
}

image_build_resolve_dockerfile() {
  local category="$1"
  local image_id="$2"
  local context_dir="$3"
  local dockerfile="$4"

  [ -n "${dockerfile}" ] || { echo "${0##*/}: ${category}.${image_id} is missing build.dockerfile in image catalog" >&2; exit 1; }
  if [ -f "${REPO_ROOT}/${dockerfile}" ]; then
    printf '%s/%s\n' "${REPO_ROOT}" "${dockerfile}"
  else
    printf '%s/%s\n' "${context_dir}" "${dockerfile}"
  fi
}

image_build_cache_hit() {
  local repo="$1"
  local version_tag="$2"
  local latest_tag="$3"
  local fingerprint_tag="$4"
  local commit_tag="$5"

  [ "${FORCE_REBUILD:-0}" != "1" ] || return 1
  image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${version_tag}" || return 1
  image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${latest_tag}" || return 1
  if [ -n "${fingerprint_tag}" ]; then
    image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}" || return 1
  fi
  if [ "${IMAGE_BUILD_REQUIRE_COMMIT_TAG:-0}" = "1" ]; then
    [ -n "${commit_tag}" ] || return 1
    image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${commit_tag}" || return 1
  fi

  return 0
}

image_build_tag_and_push() {
  local build_ref="$1"
  local target_ref="$2"

  docker tag "${build_ref}" "${target_ref}"
  image_build_push_ref "${target_ref}"
  if declare -F image_signing_sign_ref >/dev/null 2>&1; then
    image_signing_sign_ref "${target_ref}"
  fi
}

image_build_push_optional_tag() {
  local build_ref="$1"
  local target_ref="$2"
  shift 2
  local existing_ref=""

  [ -n "${target_ref}" ] || return 0
  for existing_ref in "$@"; do
    if [ "${target_ref}" = "${existing_ref}" ]; then
      return 0
    fi
  done

  image_build_tag_and_push "${build_ref}" "${target_ref}"
}

image_build_build_and_push_cached() {
  local image_name="$1"
  local build_context="$2"
  local dockerfile_path="$3"
  local version_tag="${4:-${TAG:-latest}}"
  local fingerprint_tag="$5"
  shift 5

  local repo="${IMAGE_NAMESPACE}/${image_name}"
  local latest_tag="${TAG:-latest}"
  local build_ref="build-${image_name}:${version_tag}"
  local latest_ref="${CACHE_PUSH_HOST}/${repo}:${latest_tag}"
  local version_ref="${CACHE_PUSH_HOST}/${repo}:${version_tag}"
  local commit_tag=""
  local commit_ref=""
  local fingerprint_ref=""
  local cmd=()

  commit_tag="$(image_build_commit_tag)"
  if [ -n "${commit_tag}" ]; then
    commit_ref="${CACHE_PUSH_HOST}/${repo}:${commit_tag}"
  fi
  if [ -n "${fingerprint_tag}" ]; then
    fingerprint_ref="${CACHE_PUSH_HOST}/${repo}:${fingerprint_tag}"
  fi

  if image_build_cache_hit "${repo}" "${version_tag}" "${latest_tag}" "${fingerprint_tag}" "${commit_tag}"; then
    echo "OK   cached ${version_ref}"
    if declare -F image_signing_sign_ref >/dev/null 2>&1; then
      image_signing_sign_ref "${version_ref}"
      image_signing_sign_ref "${latest_ref}"
      image_signing_sign_ref "${commit_ref}"
      image_signing_sign_ref "${fingerprint_ref}"
    fi
    return 0
  fi

  echo "BUILD ${image_name}"
  cmd=(-t "${build_ref}" -f "${dockerfile_path}")
  while [[ $# -gt 0 ]]; do
    cmd+=("$1")
    shift
  done
  cmd+=("${build_context}")
  image_build_run_docker "${cmd[@]}"

  image_build_tag_and_push "${build_ref}" "${version_ref}"
  image_build_push_optional_tag "${build_ref}" "${latest_ref}" "${version_ref}"
  image_build_push_optional_tag "${build_ref}" "${commit_ref}" "${version_ref}" "${latest_ref}"
  image_build_push_optional_tag "${build_ref}" "${fingerprint_ref}" "${version_ref}" "${latest_ref}" "${commit_ref}"

  echo "PUSH  ${version_ref}"
}

image_build_catalog_build_and_push() {
  local category="$1"
  local image_id="$2"
  local image_name="$3"
  local fingerprint_tag="${4:-}"
  local version_tag="${5:-}"
  local context=""
  local dockerfile=""
  local context_dir=""
  local dockerfile_path=""

  if [ -z "${version_tag}" ]; then
    version_tag="$(image_catalog_default_tag "${category}" "${image_id}")"
  fi
  if [ -z "${fingerprint_tag}" ]; then
    fingerprint_tag="$(image_catalog_source_tag "${category}" "${image_id}")"
  fi
  context="$(image_catalog_build_field "${category}" "${image_id}" context)"
  dockerfile="$(image_catalog_build_field "${category}" "${image_id}" dockerfile)"
  image_build_run_prebuild "${category}" "${image_id}"
  context_dir="$(image_build_resolve_context "${category}" "${image_id}" "${context}")"
  dockerfile_path="$(image_build_resolve_dockerfile "${category}" "${image_id}" "${context_dir}" "${dockerfile}")"
  image_build_prepare_args "${category}" "${image_id}"
  if [[ "${#IMAGE_BUILD_ARGS[@]}" -gt 0 ]]; then
    image_build_build_and_push_cached \
      "${image_name}" \
      "${context_dir}" \
      "${dockerfile_path}" \
      "${version_tag}" \
      "${fingerprint_tag}" \
      "${IMAGE_BUILD_ARGS[@]}"
  else
    image_build_build_and_push_cached \
      "${image_name}" \
      "${context_dir}" \
      "${dockerfile_path}" \
      "${version_tag}" \
      "${fingerprint_tag}"
  fi
}

image_build_catalog_build_loop() {
  local category="$1"
  local builder="$2"
  local image_id=""
  local image_name=""
  local _build_context=""
  local _dockerfile_path=""
  local _build_tag=""

  while IFS=$'\t' read -r image_id image_name _build_context _dockerfile_path _build_tag; do
    [ -n "${image_id}" ] || continue
    image_build_catalog_build_and_push "${category}" "${image_id}" "${image_name}"
  done < <(image_catalog_build_specs "${category}" "${builder}")
}
