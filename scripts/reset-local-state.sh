#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

WORKSPACE_ROOT="${RESET_LOCAL_STATE_WORKSPACE_ROOT:-${REPO_ROOT}}"
GIT_ROOT="${RESET_LOCAL_STATE_GIT_ROOT:-${WORKSPACE_ROOT}}"
DOCKER_PRUNE_ESTIMATE_SCRIPT="${DOCKER_PRUNE_ESTIMATE_SCRIPT:-${REPO_ROOT}/kubernetes/kind/scripts/docker-prune-estimate.sh}"
CACHE_CONTAINER_NAME="${CACHE_CONTAINER_NAME:-platform-local-image-cache}"
NPM_CACHE_DIR_OVERRIDE="${RESET_LOCAL_STATE_NPM_CACHE_DIR:-}"
BUN_CACHE_DIR_OVERRIDE="${RESET_LOCAL_STATE_BUN_CACHE_DIR:-${HOME}/.bun/install/cache}"
UV_CACHE_DIR_OVERRIDE="${RESET_LOCAL_STATE_UV_CACHE_DIR:-}"
PLAYWRIGHT_CACHE_DIR_OVERRIDE="${RESET_LOCAL_STATE_PLAYWRIGHT_CACHE_DIR:-}"
PIP_CACHE_DIR_OVERRIDE="${RESET_LOCAL_STATE_PIP_CACHE_DIR:-}"
KIND_KUBECONFIG_PATH="${RESET_LOCAL_STATE_KIND_KUBECONFIG_PATH:-${HOME}/.kube/kind-kind-local.yaml}"
LIMA_KUBECONFIG_PATH="${RESET_LOCAL_STATE_LIMA_KUBECONFIG_PATH:-${HOME}/.kube/limavm-k3s.yaml}"
SLICER_KUBECONFIG_PATH="${RESET_LOCAL_STATE_SLICER_KUBECONFIG_PATH:-${HOME}/.kube/slicer-k3s.yaml}"

INCLUDE_HOST_CACHES=0
INCLUDE_KUBECONFIGS=0
INCLUDE_DOCKER=0
INCLUDE_DOCKER_VOLUMES=0

repo_paths=()
host_paths=()
skipped_tracked_paths=()

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] [options]

Remove repo-generated local state so the workspace is closer to a fresh clone.

Options:
  --include-host-caches    Also remove host caches such as npm, Bun, and uv.
  --include-kubeconfigs    Also remove repo-owned split kubeconfigs under ~/.kube.
  --include-docker         Also remove the local registry container and run Docker prune commands.
  --include-docker-volumes Also run docker volume prune -f (global, destructive).
$(shell_cli_standard_options)
EOF
}

human_kib() {
  local kib="${1:-0}"
  awk -v kib="${kib}" '
    BEGIN {
      split("KiB MiB GiB TiB PiB", units, " ")
      value = kib + 0
      idx = 1
      while (value >= 1024 && idx < 5) {
        value /= 1024
        idx++
      }
      if (idx == 1) {
        printf "%.0f %s\n", value, units[idx]
      } else {
        printf "%.2f %s\n", value, units[idx]
      }
    }
  '
}

path_kib() {
  local path="${1}"
  du -sk "${path}" 2>/dev/null | awk '{print $1}'
}

path_is_tracked() {
  local path="${1}"
  local rel=""

  if [[ ! -d "${GIT_ROOT}/.git" ]]; then
    return 1
  fi

  rel="${path#${GIT_ROOT}/}"
  if [[ "${rel}" == "${path}" ]]; then
    return 1
  fi

  [[ -n "$(git -C "${GIT_ROOT}" ls-files -- "${rel}" 2>/dev/null || true)" ]]
}

append_unique_path() {
  local array_name="${1}"
  local path="${2}"
  local existing=""

  eval "for existing in \${${array_name}[@]+\"\${${array_name}[@]}\"}; do
    if [[ \"\${existing}\" == \"${path}\" ]]; then
      return 0
    fi
  done"

  eval "${array_name}+=(\"\${path}\")"
}

collect_repo_paths() {
  local path=""
  while IFS= read -r -d '' path; do
    if path_is_tracked "${path}"; then
      append_unique_path skipped_tracked_paths "${path}"
      continue
    fi
    append_unique_path repo_paths "${path}"
  done < <(
    find "${WORKSPACE_ROOT}" \
      \( -path "${WORKSPACE_ROOT}/.git" -o -path '*/.git' \) -prune -o \
      -type d \
      \( \
        -name .run -o \
        -name node_modules -o \
        -name .terraform -o \
        -name .terragrunt-cache -o \
        -name .pytest_cache -o \
        -name .mypy_cache -o \
        -name .ruff_cache -o \
        -name .venv -o \
        -name venv -o \
        -name .vite -o \
        -name coverage -o \
        -name playwright-report -o \
        -name test-results -o \
        -name dist -o \
        -name build \
      \) \
      -prune -print0
  )
}

collect_host_paths() {
  local npm_cache_dir=""
  local uv_cache_dir=""
  local pip_cache_dir=""
  local playwright_cache_dir=""
  local candidate=""

  if [[ "${INCLUDE_HOST_CACHES}" -eq 1 ]]; then
    npm_cache_dir="${NPM_CACHE_DIR_OVERRIDE}"
    if [[ -z "${npm_cache_dir}" ]] && command -v npm >/dev/null 2>&1; then
      npm_cache_dir="$(npm config get cache 2>/dev/null || true)"
    fi
    if [[ -n "${npm_cache_dir}" && -e "${npm_cache_dir}" ]]; then
      append_unique_path host_paths "${npm_cache_dir}"
    fi

    if [[ -n "${BUN_CACHE_DIR_OVERRIDE}" && -e "${BUN_CACHE_DIR_OVERRIDE}" ]]; then
      append_unique_path host_paths "${BUN_CACHE_DIR_OVERRIDE}"
    fi

    uv_cache_dir="${UV_CACHE_DIR_OVERRIDE}"
    if [[ -z "${uv_cache_dir}" ]] && command -v uv >/dev/null 2>&1; then
      uv_cache_dir="$(uv cache dir 2>/dev/null || true)"
    fi
    if [[ -n "${uv_cache_dir}" && -e "${uv_cache_dir}" ]]; then
      append_unique_path host_paths "${uv_cache_dir}"
    fi

    playwright_cache_dir="${PLAYWRIGHT_CACHE_DIR_OVERRIDE}"
    if [[ -n "${playwright_cache_dir}" ]]; then
      if [[ -e "${playwright_cache_dir}" ]]; then
        append_unique_path host_paths "${playwright_cache_dir}"
      fi
    else
      for candidate in \
        "${HOME}/Library/Caches/ms-playwright" \
        "${HOME}/.cache/ms-playwright"
      do
        if [[ -e "${candidate}" ]]; then
          append_unique_path host_paths "${candidate}"
        fi
      done
    fi

    pip_cache_dir="${PIP_CACHE_DIR_OVERRIDE}"
    if [[ -z "${pip_cache_dir}" ]] && command -v pip >/dev/null 2>&1; then
      pip_cache_dir="$(pip cache dir 2>/dev/null || true)"
    fi
    if [[ -n "${pip_cache_dir}" ]]; then
      if [[ -e "${pip_cache_dir}" ]]; then
        append_unique_path host_paths "${pip_cache_dir}"
      fi
    else
      for candidate in \
        "${HOME}/Library/Caches/pip" \
        "${HOME}/.cache/pip"
      do
        if [[ -e "${candidate}" ]]; then
          append_unique_path host_paths "${candidate}"
        fi
      done
    fi
  fi

  if [[ "${INCLUDE_KUBECONFIGS}" -eq 1 ]]; then
    if [[ -e "${KIND_KUBECONFIG_PATH}" ]]; then
      append_unique_path host_paths "${KIND_KUBECONFIG_PATH}"
    fi
    if [[ -e "${LIMA_KUBECONFIG_PATH}" ]]; then
      append_unique_path host_paths "${LIMA_KUBECONFIG_PATH}"
    fi
    if [[ -e "${SLICER_KUBECONFIG_PATH}" ]]; then
      append_unique_path host_paths "${SLICER_KUBECONFIG_PATH}"
    fi
  fi
}

paths_total_kib() {
  local array_name="${1}"
  local total=0
  local path=""
  local kib=0

  eval "for path in \"\${${array_name}[@]}\"; do
    kib=\$(path_kib \"\${path}\" 2>/dev/null || printf '0')
    total=\$((total + kib))
  done"

  printf '%s\n' "${total}"
}

print_path_group() {
  local title="${1}"
  local array_name="${2}"
  local total=0
  local path=""
  local kib=0

  eval "local count=\${#${array_name}[@]}"
  eval "if [[ \${count} -eq 0 ]]; then
    printf '%s\n' \"${title}:\"
    printf '  none\n'
    return 0
  fi"

  total="$(paths_total_kib "${array_name}")"
  printf '%s\n' "${title}:"
  printf '  total: %s\n' "$(human_kib "${total}")"
  eval "for path in \"\${${array_name}[@]}\"; do
    kib=\$(path_kib \"\${path}\" 2>/dev/null || printf '0')
    printf '  %s (%s)\n' \"\${path}\" \"\$(human_kib \"\${kib}\")\"
  done"
}

print_skipped_paths() {
  local path=""
  if [[ "${#skipped_tracked_paths[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "Skipping tracked path(s):"
  for path in ${skipped_tracked_paths[@]+"${skipped_tracked_paths[@]}"}; do
    printf '  %s\n' "${path}"
  done
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

print_docker_plan() {
  if [[ "${INCLUDE_DOCKER}" -ne 1 ]]; then
    return 0
  fi

  printf '%s\n' "Docker actions:"
  printf '  remove container: %s\n' "${CACHE_CONTAINER_NAME}"
  printf '  docker builder prune -af\n'
  printf '  docker system prune -af\n'
  if [[ "${INCLUDE_DOCKER_VOLUMES}" -eq 1 ]]; then
    printf '  docker volume prune -f\n'
  fi

  if docker_ready && [[ -x "${DOCKER_PRUNE_ESTIMATE_SCRIPT}" ]]; then
    printf '\n'
    "${DOCKER_PRUNE_ESTIMATE_SCRIPT}" --execute
  elif [[ "${INCLUDE_DOCKER}" -eq 1 ]]; then
    printf '  note: docker prune estimate unavailable in the current shell\n'
  fi
}

preview_body() {
  collect_repo_paths
  collect_host_paths

  printf '%s\n' "Cold-start reset preview"
  printf '  workspace: %s\n' "${WORKSPACE_ROOT}"
  printf '  include host caches: %s\n' "${INCLUDE_HOST_CACHES}"
  printf '  include kubeconfigs: %s\n' "${INCLUDE_KUBECONFIGS}"
  printf '  include docker: %s\n' "${INCLUDE_DOCKER}"
  printf '  include docker volumes: %s\n' "${INCLUDE_DOCKER_VOLUMES}"
  printf '\n'
  print_path_group "Repo-owned generated paths" repo_paths
  printf '\n'
  print_path_group "Host paths" host_paths
  if [[ "${INCLUDE_DOCKER}" -eq 1 ]]; then
    printf '\n'
    print_docker_plan
  fi
  if [[ "${#skipped_tracked_paths[@]}" -gt 0 ]]; then
    printf '\n'
    print_skipped_paths
  fi
}

preview() {
  shell_cli_print_dry_run_summary "would preview repo-generated local state cleanup"
  preview_body
}

remove_paths() {
  local array_name="${1}"
  local path=""

  eval "for path in \"\${${array_name}[@]}\"; do
    rm -rf \"\${path}\"
    printf 'removed %s\n' \"\${path}\"
  done"
}

run_execute() {
  collect_repo_paths
  collect_host_paths

  preview_body
  printf '\n'
  remove_paths repo_paths
  remove_paths host_paths

  if [[ "${INCLUDE_DOCKER}" -eq 1 ]]; then
    if ! docker_ready; then
      printf '%s\n' "WARN docker daemon not reachable; skipping docker cleanup"
    else
      docker rm -f "${CACHE_CONTAINER_NAME}" >/dev/null 2>&1 || true
      docker builder prune -af
      docker system prune -af
      if [[ "${INCLUDE_DOCKER_VOLUMES}" -eq 1 ]]; then
        docker volume prune -f
      fi
    fi
  fi
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --include-host-caches)
      INCLUDE_HOST_CACHES=1
      shift
      ;;
    --include-kubeconfigs)
      INCLUDE_KUBECONFIGS=1
      shift
      ;;
    --include-docker)
      INCLUDE_DOCKER=1
      shift
      ;;
    --include-docker-volumes)
      INCLUDE_DOCKER=1
      INCLUDE_DOCKER_VOLUMES=1
      shift
      ;;
    *)
      shell_cli_unknown_flag "$(basename "$0")" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview usage preview
run_execute
