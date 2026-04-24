#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEVCONTAINER_CONFIG="${DEVCONTAINER_CONFIG:-${REPO_ROOT}/.devcontainer/devcontainer.json}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
DEVCONTAINER_CLI="${DEVCONTAINER_CLI:-devcontainer}"
CONTAINER_MARKER_FILE="${CONTAINER_MARKER_FILE:-/.dockerenv}"
CONTAINER_SHELL="${CONTAINER_SHELL:-zsh -l}"
DEVCONTAINER_DOCKER_SMOKE_TIMEOUT_SECONDS="${DEVCONTAINER_DOCKER_SMOKE_TIMEOUT_SECONDS:-30}"
DEVCONTAINER_DOCKER_RM_TIMEOUT_SECONDS="${DEVCONTAINER_DOCKER_RM_TIMEOUT_SECONDS:-30}"
DEVCONTAINER_BUILD_TIMEOUT_SECONDS="${DEVCONTAINER_BUILD_TIMEOUT_SECONDS:-300}"
DEVCONTAINER_UP_TIMEOUT_SECONDS="${DEVCONTAINER_UP_TIMEOUT_SECONDS:-180}"
DEVCONTAINER_DIAGNOSTIC_TIMEOUT_SECONDS="${DEVCONTAINER_DIAGNOSTIC_TIMEOUT_SECONDS:-10}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

ACTION=""

usage() {
  cat <<EOF
Usage: host-lifecycle.sh --action <build|run|exec> [--dry-run] [--execute]

Runs the platform devcontainer lifecycle from the host with smoke preflights,
bounded waits, and Docker diagnostics on failure.

$(shell_cli_standard_options)

Options:
  --action <build|run|exec>  Host lifecycle action to run

Environment:
  DEVCONTAINER_DOCKER_SMOKE_TIMEOUT_SECONDS=30  Timeout for docker build smoke checks.
  DEVCONTAINER_DOCKER_RM_TIMEOUT_SECONDS=30     Timeout for stale workspace container cleanup.
  DEVCONTAINER_BUILD_TIMEOUT_SECONDS=300        Timeout for devcontainer build.
  DEVCONTAINER_UP_TIMEOUT_SECONDS=180           Timeout for devcontainer up before attach.
  DEVCONTAINER_DIAGNOSTIC_TIMEOUT_SECONDS=10    Timeout for each Docker diagnostic command.
EOF
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*"
}

inside_devcontainer() {
  [[ "${PLATFORM_DEVCONTAINER:-}" == "1" ]] || [[ -f "${CONTAINER_MARKER_FILE}" ]]
}

parse_args() {
  local script_name

  script_name="$(shell_cli_script_name)"
  shell_cli_init_standard_flags

  while [[ $# -gt 0 ]]; do
    if shell_cli_handle_standard_flag usage "$1"; then
      shift
      continue
    fi

    case "$1" in
      --action)
        shift
        [[ $# -gt 0 ]] || {
          shell_cli_missing_value "${script_name}" "--action"
          exit 1
        }
        ACTION="$1"
        ;;
      --action=*)
        ACTION="${1#*=}"
        ;;
      --)
        shift
        break
        ;;
      -*)
        shell_cli_unknown_flag "${script_name}" "$1"
        exit 1
        ;;
      *)
        shell_cli_unexpected_arg "${script_name}" "$1"
        exit 1
        ;;
    esac
    shift
  done

  case "${ACTION}" in
    build|run|exec)
      ;;
    "")
      fail "host-lifecycle.sh: missing required flag: --action"
      ;;
    *)
      fail "host-lifecycle.sh: unsupported action: ${ACTION}"
      ;;
  esac

  shell_cli_maybe_execute_or_preview_summary usage "would run the ${ACTION} devcontainer lifecycle with smoke preflights and bounded waits"
}

process_children() {
  local target_pid="$1"

  ps -Ao pid=,ppid= | awk -v target="${target_pid}" '$2 == target { print $1 }'
}

kill_process_tree() {
  local target_pid="$1"
  local signal_name="$2"
  local child_pid=""

  while IFS= read -r child_pid; do
    [[ -n "${child_pid}" ]] || continue
    kill_process_tree "${child_pid}" "${signal_name}"
  done < <(process_children "${target_pid}")

  if kill -0 "${target_pid}" >/dev/null 2>&1; then
    kill "-${signal_name}" "${target_pid}" >/dev/null 2>&1 || true
  fi
}

run_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2
  local timeout_flag runner_pid watcher_pid exit_code
  local -a command=("$@")

  timeout_flag="$(mktemp)"
  rm -f "${timeout_flag}"

  "${command[@]}" &
  runner_pid=$!

  (
    sleep "${timeout_seconds}"
    if kill -0 "${runner_pid}" >/dev/null 2>&1; then
      printf 'Timed out after %ss: %s\n' "${timeout_seconds}" "${label}" >&2
      printf 'timeout\n' >"${timeout_flag}"
      kill_process_tree "${runner_pid}" TERM
      sleep 2
      kill_process_tree "${runner_pid}" KILL
    fi
  ) &
  watcher_pid=$!

  exit_code=0
  if wait "${runner_pid}"; then
    exit_code=0
  else
    exit_code=$?
  fi

  kill_process_tree "${watcher_pid}" TERM
  wait "${watcher_pid}" >/dev/null 2>&1 || true

  rm -f "${timeout_flag}"

  return "${exit_code}"
}

run_diagnostic() {
  local label="$1"
  local exit_code=0
  shift

  printf '\n[%s]\n' "${label}" >&2
  if run_with_timeout "${DEVCONTAINER_DIAGNOSTIC_TIMEOUT_SECONDS}" "diagnostic: ${label}" "$@"; then
    return 0
  fi

  exit_code=$?
  printf 'WARN diagnostic did not complete cleanly: %s (exit %s)\n' "${label}" "${exit_code}" >&2
  return 0
}

workspace_container_ids() {
  "${DOCKER_BIN}" ps -aq \
    --filter "label=devcontainer.local_folder=${REPO_ROOT}" \
    --filter "label=devcontainer.config_file=${DEVCONTAINER_CONFIG}"
}

print_failure_diagnostics() {
  printf '\nDocker diagnostics for %s\n' "${ACTION}" >&2
  run_diagnostic "docker buildx version" "${DOCKER_BIN}" buildx version
  run_diagnostic "docker buildx ls" "${DOCKER_BIN}" buildx ls
  run_diagnostic "docker system df" "${DOCKER_BIN}" system df
  run_diagnostic \
    "workspace containers" \
    "${DOCKER_BIN}" ps -a \
    --filter "label=devcontainer.local_folder=${REPO_ROOT}" \
    --filter "label=devcontainer.config_file=${DEVCONTAINER_CONFIG}"
  run_diagnostic "workspace images" bash -lc \
    "\"${DOCKER_BIN}\" images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}' | awk '/^vsc-platform/ { print }'"
}

smoke_context_dir() {
  local temp_dir="$1"

  mkdir -p "${temp_dir}"
  cat >"${temp_dir}/Dockerfile" <<'EOF'
FROM scratch
LABEL org.platform.devcontainer.smoke="true"
EOF
}

run_docker_smoke() {
  local tag="$1"
  shift
  local temp_dir exit_code
  local -a command=("$@")

  temp_dir="$(mktemp -d)"
  smoke_context_dir "${temp_dir}"
  exit_code=0
  if run_with_timeout "${DEVCONTAINER_DOCKER_SMOKE_TIMEOUT_SECONDS}" "${command[*]}" "${command[@]}" "${temp_dir}"; then
    :
  else
    exit_code=$?
    rm -rf "${temp_dir}"
    "${DOCKER_BIN}" image rm -f "${tag}" >/dev/null 2>&1 || true
    return "${exit_code}"
  fi
  rm -rf "${temp_dir}"
  "${DOCKER_BIN}" image rm -f "${tag}" >/dev/null 2>&1 || true
}

run_smoke_preflight() {
  local smoke_tag_base smoke_tag_build smoke_tag_buildx

  smoke_tag_base="platform-devcontainer-smoke-$$"
  smoke_tag_build="${smoke_tag_base}:docker-build"
  smoke_tag_buildx="${smoke_tag_base}:docker-buildx-load"

  log "Smoke check: docker build"
  run_docker_smoke "${smoke_tag_build}" "${DOCKER_BIN}" build -t "${smoke_tag_build}" >/dev/null

  log "Smoke check: docker buildx build --load"
  run_docker_smoke "${smoke_tag_buildx}" "${DOCKER_BIN}" buildx build --load -t "${smoke_tag_buildx}" >/dev/null
}

remove_existing_workspace_containers() {
  local existing_ids=""
  local existing_id=""
  local exit_code=0
  local -a existing_id_args=()

  existing_ids="$(workspace_container_ids)"
  if [[ -z "${existing_ids}" ]]; then
    return 0
  fi

  while IFS= read -r existing_id; do
    [[ -n "${existing_id}" ]] || continue
    existing_id_args+=("${existing_id}")
  done <<< "${existing_ids}"

  log "Removing existing devcontainer container(s): ${existing_ids}"

  if run_with_timeout "${DEVCONTAINER_DOCKER_RM_TIMEOUT_SECONDS}" "docker rm -f ${existing_ids}" "${DOCKER_BIN}" rm -f "${existing_id_args[@]}"; then
    return 0
  fi

  exit_code=$?
  return "${exit_code}"
}

run_action() {
  case "${ACTION}" in
    build)
      remove_existing_workspace_containers
      run_with_timeout \
        "${DEVCONTAINER_BUILD_TIMEOUT_SECONDS}" \
        "devcontainer build --workspace-folder ${REPO_ROOT}" \
        "${DEVCONTAINER_CLI}" build --workspace-folder "${REPO_ROOT}"
      ;;
    run)
      run_with_timeout \
        "${DEVCONTAINER_UP_TIMEOUT_SECONDS}" \
        "devcontainer up --workspace-folder ${REPO_ROOT}" \
        "${DEVCONTAINER_CLI}" up --workspace-folder "${REPO_ROOT}"
      ;;
    exec)
      run_with_timeout \
        "${DEVCONTAINER_UP_TIMEOUT_SECONDS}" \
        "devcontainer up --workspace-folder ${REPO_ROOT}" \
        "${DEVCONTAINER_CLI}" up --workspace-folder "${REPO_ROOT}"
      # shellcheck disable=SC2086 # container shell flags are intentionally split
      "${DEVCONTAINER_CLI}" exec --workspace-folder "${REPO_ROOT}" ${CONTAINER_SHELL}
      ;;
  esac
}

main() {
  local exit_code=0

  parse_args "$@"

  if inside_devcontainer; then
    case "${ACTION}" in
      build)
        fail "make -C .devcontainer build must be run from the host, not from inside the devcontainer."
        ;;
      run)
        fail "make -C .devcontainer run must be run from the host. You are already inside the devcontainer."
        ;;
      exec)
        fail "make -C .devcontainer exec must be run from the host. You are already inside the devcontainer."
        ;;
    esac
  fi

  if run_smoke_preflight; then
    :
  else
    exit_code=$?
    print_failure_diagnostics
    exit "${exit_code}"
  fi

  if run_action; then
    :
  else
    exit_code=$?
    print_failure_diagnostics
    exit "${exit_code}"
  fi
}

main "$@"
