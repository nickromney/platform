#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

INCLUDE_BUILDER_CACHE=1
INCLUDE_DANGLING_IMAGES=1
INCLUDE_STOPPED_CONTAINERS=1
INCLUDE_UNUSED_IMAGES=1
BUILDER_CACHE_UNTIL="${BUILDER_CACHE_UNTIL:-24h}"
KIND_CONTAINER_PREFIX="${KIND_CONTAINER_PREFIX:-kind-local-}"
CACHE_CONTAINER_NAME="${CACHE_CONTAINER_NAME:-platform-local-image-cache}"
PROTECTED_IMAGE_REF_REGEX="${PROTECTED_IMAGE_REF_REGEX:-^(kindest/node:|registry:|127[.]0[.]0[.]1:5002/platform/|host[.]docker[.]internal:5002/platform/)}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] [options]

Run a conservative Docker cleanup that preserves the current kind cluster shape.

By default this prunes Docker build cache unused for at least 24 hours, dangling
images, unused non-protected tagged images, and stopped containers except kind
node containers and the local platform image-cache registry. It does not run
docker system prune -a and never prunes volumes.

Options:
  --skip-builder-cache       Do not run docker builder prune.
  --skip-dangling-images     Do not run docker image prune -f.
  --skip-unused-images       Do not remove unused tagged images.
  --skip-stopped-containers  Do not remove stopped non-kind containers.
  --builder-cache-until AGE  Prune builder cache unused since AGE (default: 24h).
$(shell_cli_standard_options)
EOF
}

fail() {
  echo "docker-safe-clean: $*" >&2
  exit 1
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

require_docker() {
  command -v docker >/dev/null 2>&1 || fail "docker not found in PATH"
  docker info >/dev/null 2>&1 || fail "docker daemon is not reachable"
}

print_docker_df() {
  echo "Docker disk usage:"
  docker system df 2>/dev/null || echo "  docker system df unavailable"
}

print_preserved_containers() {
  echo "Preserved containers:"
  docker ps -a \
    --filter "name=^/${KIND_CONTAINER_PREFIX}" \
    --filter "name=^/${CACHE_CONTAINER_NAME}$" \
    --format '  {{.Names}}	{{.Image}}	{{.Status}}' |
    sed '/^$/d' || true
}

stopped_container_ids_to_remove() {
  docker ps -a \
    --filter "status=created" \
    --filter "status=exited" \
    --filter "status=dead" \
    --format '{{.ID}}	{{.Names}}' |
    awk -v kind_prefix="${KIND_CONTAINER_PREFIX}" -v cache_name="${CACHE_CONTAINER_NAME}" '
      $2 == cache_name { next }
      index($2, kind_prefix) == 1 { next }
      { print $1 }
    '
}

used_image_ids() {
  local image_ref=""

  docker ps -a --format '{{.Image}}' |
    while IFS= read -r image_ref; do
      [[ -z "${image_ref}" ]] && continue
      docker image inspect --format '{{.Id}}' "${image_ref}" 2>/dev/null || true
    done |
    sed 's/^sha256://' |
    LC_ALL=C sort -u
}

protected_image_ids() {
  docker image ls --format '{{.ID}}	{{.Repository}}:{{.Tag}}' |
    awk -F '\t' -v protected_regex="${PROTECTED_IMAGE_REF_REGEX}" '
      $2 ~ protected_regex { print $1 }
    ' |
    LC_ALL=C sort -u
}

unused_image_rows() {
  local used_file=""
  local protected_file=""

  used_file="$(mktemp "${TMPDIR:-/tmp}/docker-safe-clean-used.XXXXXX")"
  protected_file="$(mktemp "${TMPDIR:-/tmp}/docker-safe-clean-protected.XXXXXX")"
  trap 'rm -f "${used_file}" "${protected_file}"' RETURN

  used_image_ids >"${used_file}"
  protected_image_ids >"${protected_file}"

  docker image ls --format '{{.ID}}	{{.Repository}}:{{.Tag}}	{{.Size}}' |
    awk -F '\t' -v used_file="${used_file}" -v protected_file="${protected_file}" '
      BEGIN {
        while ((getline line < used_file) > 0) {
          if (line != "") used_map[line] = 1
        }
        close(used_file)
        while ((getline line < protected_file) > 0) {
          if (line != "") protected_map[line] = 1
        }
        close(protected_file)
      }
      $2 ~ /:<none>$/ { next }
      used_map[$1] { next }
      protected_map[$1] { next }
      seen[$1] { next }
      {
        seen[$1] = 1
        print $0
      }
    '
}

unused_image_ids_to_remove() {
  unused_image_rows | awk -F '\t' '{ print $1 }'
}

print_stopped_container_plan() {
  local rows=""

  rows="$(
    docker ps -a \
      --filter "status=created" \
      --filter "status=exited" \
      --filter "status=dead" \
      --format '{{.Names}}	{{.Image}}	{{.Status}}' |
      awk -v kind_prefix="${KIND_CONTAINER_PREFIX}" -v cache_name="${CACHE_CONTAINER_NAME}" '
        $1 == cache_name { next }
        index($1, kind_prefix) == 1 { next }
        { print "  " $0 }
      '
  )"

  echo "Stopped non-kind containers to remove:"
  if [[ -n "${rows}" ]]; then
    printf '%s\n' "${rows}"
  else
    echo "  none"
  fi
}

print_unused_image_plan() {
  local rows=""
  local total_count=0

  rows="$(unused_image_rows)"
  total_count="$(printf '%s\n' "${rows}" | sed '/^$/d' | wc -l | tr -d ' ')"

  echo "Unused non-protected tagged images to remove:"
  if [[ "${total_count}" -eq 0 ]]; then
    echo "  none"
    return 0
  fi

  printf '%s\n' "${rows}" |
    sed -n '1,25p' |
    awk -F '\t' '{ printf "  %s\t%s\t%s\n", $1, $2, $3 }'
  if [[ "${total_count}" -gt 25 ]]; then
    printf '  ... %s more\n' "$((total_count - 25))"
  fi
}

print_plan() {
  if docker_ready; then
    print_docker_df
    echo ""
    print_preserved_containers
    echo ""
    print_stopped_container_plan
    echo ""
    if [[ "${INCLUDE_UNUSED_IMAGES}" -eq 1 ]]; then
      print_unused_image_plan
      echo ""
    fi
  fi

  echo "Cleanup actions:"
  if [[ "${INCLUDE_BUILDER_CACHE}" -eq 1 ]]; then
    echo "  docker builder prune -f --filter until=${BUILDER_CACHE_UNTIL}"
  fi
  if [[ "${INCLUDE_DANGLING_IMAGES}" -eq 1 ]]; then
    echo "  docker image prune -f"
  fi
  if [[ "${INCLUDE_UNUSED_IMAGES}" -eq 1 ]]; then
    echo "  docker rmi -f <unused non-protected tagged images>"
  fi
  if [[ "${INCLUDE_STOPPED_CONTAINERS}" -eq 1 ]]; then
    echo "  docker rm <stopped non-kind containers>"
  fi
  echo "  skipped: docker system prune -a"
  echo "  skipped: docker volume prune"
}

preview() {
  shell_cli_print_dry_run_summary "would run conservative Docker cleanup"
  if ! docker_ready; then
    echo "docker daemon not reachable; cleanup plan cannot inspect local state"
    return 0
  fi
  print_plan
}

run_execute() {
  local ids=()
  local image_ids=()

  require_docker
  print_plan
  echo ""

  if [[ "${INCLUDE_BUILDER_CACHE}" -eq 1 ]]; then
    docker builder prune -f --filter "until=${BUILDER_CACHE_UNTIL}"
  fi

  if [[ "${INCLUDE_DANGLING_IMAGES}" -eq 1 ]]; then
    docker image prune -f
  fi

  if [[ "${INCLUDE_UNUSED_IMAGES}" -eq 1 ]]; then
    while IFS= read -r id; do
      [[ -n "${id}" ]] && image_ids+=("${id}")
    done < <(unused_image_ids_to_remove)

    if [[ "${#image_ids[@]}" -gt 0 ]]; then
      docker rmi -f "${image_ids[@]}"
    else
      echo "No unused non-protected tagged images to remove."
    fi
  fi

  if [[ "${INCLUDE_STOPPED_CONTAINERS}" -eq 1 ]]; then
    while IFS= read -r id; do
      [[ -n "${id}" ]] && ids+=("${id}")
    done < <(stopped_container_ids_to_remove)

    if [[ "${#ids[@]}" -gt 0 ]]; then
      docker rm "${ids[@]}"
    else
      echo "No stopped non-kind containers to remove."
    fi
  fi

  echo ""
  print_docker_df
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --skip-builder-cache)
      INCLUDE_BUILDER_CACHE=0
      shift
      ;;
    --skip-dangling-images)
      INCLUDE_DANGLING_IMAGES=0
      shift
      ;;
    --skip-unused-images)
      INCLUDE_UNUSED_IMAGES=0
      shift
      ;;
    --skip-stopped-containers)
      INCLUDE_STOPPED_CONTAINERS=0
      shift
      ;;
    --builder-cache-until)
      if [[ $# -lt 2 ]]; then
        shell_cli_missing_value "$(basename "$0")" "$1"
        exit 1
      fi
      BUILDER_CACHE_UNTIL="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(basename "$0")" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview usage preview
run_execute
