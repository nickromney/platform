#!/usr/bin/env bash
# shellcheck shell=bash

profile_timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

profile_default_run_id() {
  date -u +"%Y%m%d-%H%M%SZ"
}

profile_is_enabled() {
  [[ "${PLATFORM_PROFILE_MODE:-off}" != "off" ]]
}

profile_is_trace_mode() {
  [[ "${PLATFORM_PROFILE_MODE:-off}" == "trace" ]]
}

profile_validate_settings() {
  case "${PLATFORM_PROFILE_MODE:-off}" in
    off|on|trace) ;;
    *)
      echo "Invalid PLATFORM_PROFILE_MODE=${PLATFORM_PROFILE_MODE}. Expected off|on|trace." >&2
      return 1
      ;;
  esac

  case "${PLATFORM_PROFILE_CAPTURE_DOCKER:-auto}" in
    auto|on|off) ;;
    *)
      echo "Invalid PLATFORM_PROFILE_CAPTURE_DOCKER=${PLATFORM_PROFILE_CAPTURE_DOCKER}. Expected auto|on|off." >&2
      return 1
      ;;
  esac

  case "${PLATFORM_PROFILE_CAPTURE_KUBECTL:-auto}" in
    auto|on|off) ;;
    *)
      echo "Invalid PLATFORM_PROFILE_CAPTURE_KUBECTL=${PLATFORM_PROFILE_CAPTURE_KUBECTL}. Expected auto|on|off." >&2
      return 1
      ;;
  esac

  case "${PLATFORM_PROFILE_KEEP_SUCCESS:-1}" in
    0|1) ;;
    *)
      echo "Invalid PLATFORM_PROFILE_KEEP_SUCCESS=${PLATFORM_PROFILE_KEEP_SUCCESS}. Expected 0|1." >&2
      return 1
      ;;
  esac

  case "${PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE:-0}" in
    0|1) ;;
    *)
      echo "Invalid PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE=${PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE}. Expected 0|1." >&2
      return 1
      ;;
  esac
}

profile_should_capture_docker() {
  case "${PLATFORM_PROFILE_CAPTURE_DOCKER:-auto}" in
    on)
      command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
      ;;
    off)
      return 1
      ;;
    auto)
      command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
      ;;
  esac
}

profile_should_capture_kubectl() {
  case "${PLATFORM_PROFILE_CAPTURE_KUBECTL:-auto}" in
    on)
      command -v kubectl >/dev/null 2>&1
      ;;
    off)
      return 1
      ;;
    auto)
      command -v kubectl >/dev/null 2>&1
      ;;
  esac
}

profile_detect_time_command() {
  if [[ -n "${PROFILE_TIME_FORMAT_DETECTED:-}" ]]; then
    return 0
  fi

  PROFILE_TIME_COMMAND="${PROFILE_TIME_COMMAND:-/usr/bin/time}"
  PROFILE_TIME_FORMAT_DETECTED="none"

  if [[ ! -x "${PROFILE_TIME_COMMAND}" ]]; then
    return 0
  fi

  if "${PROFILE_TIME_COMMAND}" -l true >/dev/null 2>&1; then
    PROFILE_TIME_FORMAT_DETECTED="bsd"
    return 0
  fi

  if "${PROFILE_TIME_COMMAND}" -v true >/dev/null 2>&1; then
    PROFILE_TIME_FORMAT_DETECTED="gnu"
    return 0
  fi
}

profile_execute_timed() {
  local time_file="$1"
  shift

  profile_detect_time_command

  case "${PROFILE_TIME_FORMAT_DETECTED:-none}" in
    bsd)
      "${PROFILE_TIME_COMMAND}" -l -o "${time_file}" "$@"
      ;;
    gnu)
      "${PROFILE_TIME_COMMAND}" -v -o "${time_file}" "$@"
      ;;
    *)
      "$@"
      ;;
  esac
}

profile_write_versions() {
  local versions_file="${PROFILE_RUN_DIR_EFFECTIVE}/versions.txt"

  {
    printf 'timestamp=%s\n' "$(profile_timestamp_utc)"
    printf 'pwd=%s\n' "$(pwd)"
    printf 'platform_profile_mode=%s\n' "${PLATFORM_PROFILE_MODE:-off}"
    printf 'platform_profile_capture_docker=%s\n' "${PLATFORM_PROFILE_CAPTURE_DOCKER:-auto}"
    printf 'platform_profile_capture_kubectl=%s\n' "${PLATFORM_PROFILE_CAPTURE_KUBECTL:-auto}"
    printf 'platform_profile_enable_plugin_cache=%s\n' "${PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE:-0}"
    printf '\n'
    if command -v tofu >/dev/null 2>&1; then
      tofu -version 2>/dev/null
      printf '\n'
    fi
    if command -v terragrunt >/dev/null 2>&1; then
      terragrunt --version 2>/dev/null
      printf '\n'
    fi
    if command -v kubectl >/dev/null 2>&1; then
      kubectl version --client=true 2>/dev/null || true
      printf '\n'
    fi
    if command -v docker >/dev/null 2>&1; then
      docker version --format 'client={{.Client.Version}} server={{.Server.Version}}' 2>/dev/null || docker version 2>/dev/null || true
      printf '\n'
    fi
    if command -v kind >/dev/null 2>&1; then
      kind version 2>/dev/null || true
      printf '\n'
    fi
    if command -v limactl >/dev/null 2>&1; then
      limactl --version 2>/dev/null || true
      printf '\n'
    fi
    if command -v slicer >/dev/null 2>&1; then
      slicer version 2>/dev/null || slicer --version 2>/dev/null || true
    fi
  } >"${versions_file}"
}

profile_capture_host_snapshot() {
  local label="$1"
  local prefix="${PROFILE_RUN_DIR_EFFECTIVE}/${label}"

  [[ "${PROFILE_CAPTURE_DOCKER_EFFECTIVE:-0}" == "1" ]] || return 0

  docker info >"${prefix}.docker-info.txt" 2>&1 || true
  docker ps -a >"${prefix}.docker-ps.txt" 2>&1 || true
  docker system df >"${prefix}.docker-system-df.txt" 2>&1 || true
}

profile_capture_kubectl_snapshot() {
  local label="$1"
  local prefix="${PROFILE_RUN_DIR_EFFECTIVE}/${label}"

  [[ "${PROFILE_CAPTURE_KUBECTL_EFFECTIVE:-0}" == "1" ]] || return 0
  [[ -n "${PROFILE_KUBECONFIG_PATH_EFFECTIVE:-}" ]] || return 0
  [[ -f "${PROFILE_KUBECONFIG_PATH_EFFECTIVE}" ]] || return 0

  KUBECONFIG="${PROFILE_KUBECONFIG_PATH_EFFECTIVE}" kubectl config current-context >"${prefix}.kubectl-context.txt" 2>&1 || true
  KUBECONFIG="${PROFILE_KUBECONFIG_PATH_EFFECTIVE}" kubectl get nodes -o wide >"${prefix}.kubectl-nodes.txt" 2>&1 || true
  KUBECONFIG="${PROFILE_KUBECONFIG_PATH_EFFECTIVE}" kubectl get pods -A -o wide >"${prefix}.kubectl-pods.txt" 2>&1 || true
  KUBECONFIG="${PROFILE_KUBECONFIG_PATH_EFFECTIVE}" kubectl get events -A --sort-by=.lastTimestamp >"${prefix}.kubectl-events.txt" 2>&1 || true
  KUBECONFIG="${PROFILE_KUBECONFIG_PATH_EFFECTIVE}" kubectl top nodes >"${prefix}.kubectl-top-nodes.txt" 2>&1 || true
}

profile_setup_session() {
  local target="$1"
  local stage="$2"
  local action="$3"
  local kubeconfig_path="${4:-}"
  local kubeconfig_context="${5:-}"
  local run_base_dir=""
  local run_id=""

  profile_validate_settings

  PROFILE_LAST_STEP_LOG_FILE=""
  PROFILE_LAST_STEP_TIME_FILE=""

  if ! profile_is_enabled; then
    return 0
  fi

  run_base_dir="${PLATFORM_PROFILE_DIR:-$(pwd)/.run/profiles}"
  run_id="${PLATFORM_PROFILE_RUN_ID:-$(profile_default_run_id)-${target}-stage${stage}-${action}}"

  PROFILE_RUN_DIR_EFFECTIVE="${run_base_dir%/}/${run_id}"
  PROFILE_KUBECONFIG_PATH_EFFECTIVE="${kubeconfig_path}"
  PROFILE_KUBECONFIG_CONTEXT_EFFECTIVE="${kubeconfig_context}"
  PROFILE_CAPTURE_DOCKER_EFFECTIVE=0
  PROFILE_CAPTURE_KUBECTL_EFFECTIVE=0

  mkdir -p "${PROFILE_RUN_DIR_EFFECTIVE}"

  {
    printf 'step\tstarted_at\tended_at\tduration_seconds\texit_code\tlog_file\ttime_file\n'
  } >"${PROFILE_RUN_DIR_EFFECTIVE}/steps.tsv"

  {
    printf 'target=%s\n' "${target}"
    printf 'stage=%s\n' "${stage}"
    printf 'action=%s\n' "${action}"
    printf 'started_at=%s\n' "$(profile_timestamp_utc)"
    printf 'pwd=%s\n' "$(pwd)"
    printf 'kubeconfig_path=%s\n' "${kubeconfig_path}"
    printf 'kubeconfig_context=%s\n' "${kubeconfig_context}"
  } >"${PROFILE_RUN_DIR_EFFECTIVE}/metadata.env"

  profile_write_versions

  if [[ "${PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE:-0}" == "1" ]]; then
    export TF_PLUGIN_CACHE_DIR="${PLATFORM_PROFILE_PLUGIN_CACHE_DIR:-$(pwd)/.run/tofu-plugin-cache}"
    mkdir -p "${TF_PLUGIN_CACHE_DIR}"
  fi

  if profile_is_trace_mode; then
    export TF_LOG=TRACE
    export TF_LOG_PATH="${PROFILE_RUN_DIR_EFFECTIVE}/tofu-trace.log"
    export TG_LOG_LEVEL="${TG_LOG_LEVEL:-debug}"
  fi

  if profile_should_capture_docker; then
    PROFILE_CAPTURE_DOCKER_EFFECTIVE=1
    docker events --format '{{json .}}' >"${PROFILE_RUN_DIR_EFFECTIVE}/docker-events.log" 2>&1 &
    PROFILE_DOCKER_EVENTS_PID=$!
    printf '%s\n' "${PROFILE_DOCKER_EVENTS_PID}" >"${PROFILE_RUN_DIR_EFFECTIVE}/docker-events.pid"
    profile_capture_host_snapshot "start"
  fi

  if profile_should_capture_kubectl; then
    PROFILE_CAPTURE_KUBECTL_EFFECTIVE=1
    profile_capture_kubectl_snapshot "start"
  fi

  printf 'PROFILE run directory: %s\n' "${PROFILE_RUN_DIR_EFFECTIVE}"
}

profile_run_step() {
  local step="$1"
  shift

  local step_slug="${step//[^A-Za-z0-9._-]/-}"
  local log_file=""
  local time_file=""
  local started_at=""
  local ended_at=""
  local started_epoch=0
  local ended_epoch=0
  local duration_seconds=0
  local rc=0
  local use_external_time=1

  if ! profile_is_enabled; then
    "$@"
    return $?
  fi

  log_file="${PROFILE_RUN_DIR_EFFECTIVE}/${step_slug}.log"
  time_file="${PROFILE_RUN_DIR_EFFECTIVE}/${step_slug}.time"
  started_at="$(profile_timestamp_utc)"
  started_epoch="$(date +%s)"

  {
    printf 'step=%s\n' "${step}"
    printf 'started_at=%s\n' "${started_at}"
    printf 'command='
    printf '%q ' "$@"
    printf '\n\n'
  } >"${log_file}"

  if declare -F "$1" >/dev/null 2>&1; then
    use_external_time=0
  fi

  set +e
  if [[ "${use_external_time}" == "1" ]]; then
    profile_execute_timed "${time_file}" "$@" 2>&1 | tee -a "${log_file}"
  else
    "$@" 2>&1 | tee -a "${log_file}"
  fi
  rc=${PIPESTATUS[0]}
  set -e

  ended_at="$(profile_timestamp_utc)"
  ended_epoch="$(date +%s)"
  duration_seconds="$((ended_epoch - started_epoch))"

  if [[ "${use_external_time}" != "1" ]]; then
    printf 'wall_clock_seconds=%s\n' "${duration_seconds}" >"${time_file}"
  fi

  PROFILE_LAST_STEP_LOG_FILE="${log_file}"
  PROFILE_LAST_STEP_TIME_FILE="${time_file}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${step}" \
    "${started_at}" \
    "${ended_at}" \
    "${duration_seconds}" \
    "${rc}" \
    "${log_file}" \
    "${time_file}" >>"${PROFILE_RUN_DIR_EFFECTIVE}/steps.tsv"

  if [[ "${rc}" -ne 0 ]] && [[ "${PROFILE_CAPTURE_KUBECTL_EFFECTIVE:-0}" == "1" ]]; then
    profile_capture_kubectl_snapshot "failure-after-${step_slug}"
  fi

  return "${rc}"
}

profile_finish_session() {
  local rc="${1:-0}"

  if ! profile_is_enabled; then
    return 0
  fi

  profile_capture_host_snapshot "finish"
  profile_capture_kubectl_snapshot "finish"

  if [[ -n "${PROFILE_DOCKER_EVENTS_PID:-}" ]]; then
    kill "${PROFILE_DOCKER_EVENTS_PID}" >/dev/null 2>&1 || true
    wait "${PROFILE_DOCKER_EVENTS_PID}" >/dev/null 2>&1 || true
    PROFILE_DOCKER_EVENTS_PID=""
  fi

  {
    printf 'finished_at=%s\n' "$(profile_timestamp_utc)"
    printf 'exit_code=%s\n' "${rc}"
  } >"${PROFILE_RUN_DIR_EFFECTIVE}/result.env"

  if [[ "${rc}" -eq 0 ]] && [[ "${PLATFORM_PROFILE_KEEP_SUCCESS:-1}" == "0" ]]; then
    rm -rf "${PROFILE_RUN_DIR_EFFECTIVE}"
    return 0
  fi

  printf 'PROFILE artifacts kept at %s\n' "${PROFILE_RUN_DIR_EFFECTIVE}"
}
