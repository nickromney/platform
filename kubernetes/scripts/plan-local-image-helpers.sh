#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helper-mode-lib.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ --stage N --cache-mode MODE --platform-images-mode MODE --workload-images-mode MODE --prefer-external-platform-images true|false --cache-available true|false --runtime-image-cache-host HOST --push-image-cache-url URL

Purpose:
  Plan the local image helper actions needed by Lima and Slicer apply recipes.

Options:
  --stage N                         Numeric stage.
  --cache-mode MODE                 auto, on, or off for local image cache.
  --platform-images-mode MODE       auto, on, or off for platform image builds.
  --workload-images-mode MODE       auto, on, or off for workload image builds.
  --prefer-external-platform-images Whether platform images should be built.
  --cache-available true|false      Whether the push cache endpoint is reachable.
  --runtime-image-cache-host HOST   Runtime-visible cache host for diagnostics.
  --push-image-cache-url URL        Host-side cache probe URL for diagnostics.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_value() {
  local option="$1"
  local value="$2"

  if [[ -z "${value}" ]]; then
    shell_cli_missing_value "$(shell_cli_script_name)" "${option}"
    exit 1
  fi
}

validate_bool() {
  local option="$1"
  local value="$2"

  case "${value}" in
    true | false) ;;
    *)
      echo "Invalid ${option}: ${value}. Expected true or false." >&2
      exit 1
      ;;
  esac
}

stage=""
cache_mode=""
platform_images_mode=""
workload_images_mode=""
prefer_external_platform_images=""
cache_available=""
runtime_image_cache_host=""
push_image_cache_url=""

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stage)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stage"
        exit 1
      }
      stage="${2:-}"
      shift 2
      ;;
    --cache-mode)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--cache-mode"
        exit 1
      }
      cache_mode="${2:-}"
      shift 2
      ;;
    --platform-images-mode)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--platform-images-mode"
        exit 1
      }
      platform_images_mode="${2:-}"
      shift 2
      ;;
    --workload-images-mode)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--workload-images-mode"
        exit 1
      }
      workload_images_mode="${2:-}"
      shift 2
      ;;
    --prefer-external-platform-images)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--prefer-external-platform-images"
        exit 1
      }
      prefer_external_platform_images="${2:-}"
      shift 2
      ;;
    --cache-available)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--cache-available"
        exit 1
      }
      cache_available="${2:-}"
      shift 2
      ;;
    --runtime-image-cache-host)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--runtime-image-cache-host"
        exit 1
      }
      runtime_image_cache_host="${2:-}"
      shift 2
      ;;
    --push-image-cache-url)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--push-image-cache-url"
        exit 1
      }
      push_image_cache_url="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would plan local image helper actions"

require_value "--stage" "${stage}"
require_value "--cache-mode" "${cache_mode}"
require_value "--platform-images-mode" "${platform_images_mode}"
require_value "--workload-images-mode" "${workload_images_mode}"
require_value "--prefer-external-platform-images" "${prefer_external_platform_images}"
require_value "--cache-available" "${cache_available}"
require_value "--runtime-image-cache-host" "${runtime_image_cache_host}"
require_value "--push-image-cache-url" "${push_image_cache_url}"
validate_bool "--prefer-external-platform-images" "${prefer_external_platform_images}"
validate_bool "--cache-available" "${cache_available}"

stage_num=$((10#${stage}))

if helper_mode_enabled "${cache_mode}" 700 "${stage_num}"; then
  echo "ensure-image-cache"
  echo "sync-image-cache"
elif [[ "${stage_num}" -ge 700 && "${cache_available}" != "true" ]]; then
  echo "Stage ${stage} expects workload images from ${runtime_image_cache_host}, but PLATFORM_LOCAL_IMAGE_CACHE_MODE=off and no registry is reachable at ${push_image_cache_url}." >&2
  echo "Set PLATFORM_LOCAL_IMAGE_CACHE_MODE=on or start a compatible cache manually." >&2
  exit 1
fi

if [[ "${stage_num}" -ge 800 && "${prefer_external_platform_images}" = "true" ]]; then
  if helper_mode_enabled "${platform_images_mode}" 800 "${stage_num}"; then
    echo "build-local-platform-images"
  else
    echo "message:Skipping platform image build (PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=${platform_images_mode})"
  fi
fi

if [[ "${stage_num}" -ge 700 ]]; then
  if helper_mode_enabled "${workload_images_mode}" 700 "${stage_num}"; then
    echo "build-workload-images"
  else
    echo "message:Skipping workload image build (PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=${workload_images_mode})"
  fi
fi
