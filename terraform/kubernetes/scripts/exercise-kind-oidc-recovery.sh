#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/kind-apiserver-oidc-lib.sh"

OIDC_RECOVERY_FORMAT="${OIDC_RECOVERY_FORMAT:-text}"
OIDC_RECOVERY_FORCE_MODE="${OIDC_RECOVERY_FORCE_MODE:-nginx-rollout}"
OIDC_RECOVERY_FORCE_WAIT_SECONDS="${OIDC_RECOVERY_FORCE_WAIT_SECONDS:-60}"
KIND_OIDC_RECOVERY_SCRIPT="${KIND_OIDC_RECOVERY_SCRIPT:-${SCRIPT_DIR}/recover-kind-cluster-after-apiserver-restart.sh}"

json_mode() {
  [ "${OIDC_RECOVERY_FORMAT}" = "json" ]
}

usage() {
  cat <<'EOF'
Usage: exercise-kind-oidc-recovery.sh [--dry-run] [--execute]

Forces the kind post-kube-apiserver OIDC recovery branch in a controlled way,
delegates to the explicit post-restart recovery script, and verifies the
cluster returns to a healthy state.

Environment:
  OIDC_RECOVERY_FORMAT=text|json
    Output format. Json mode emits one machine-readable object on stdout.
  OIDC_RECOVERY_FORCE_MODE=nginx-rollout
    Controlled perturbation mode used to force the recovery branch.
  OIDC_RECOVERY_FORCE_WAIT_SECONDS=60
    Seconds to wait for the forced degradation to become observable.
  KIND_OIDC_RECOVERY_SCRIPT=/abs/path/script.sh
    Override the delegated recovery script.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

sanitize_record_field() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   '
}

preview_summary="would force the kind OIDC recovery branch and verify the delegated recovery step"

emit_preview_result() {
  if json_mode; then
    jq -n \
      --arg force_mode "${OIDC_RECOVERY_FORCE_MODE}" \
      --arg recovery_script "${KIND_OIDC_RECOVERY_SCRIPT}" \
      --arg summary "${preview_summary}" \
      '{
        ok: true,
        dry_run: true,
        status_code: "dry_run",
        status_group: "preview",
        summary: $summary,
        force_mode: $force_mode,
        recovery_script: $recovery_script
      }'
    return 0
  fi

  shell_cli_print_dry_run_summary "${preview_summary}"
}

shell_cli_parse_standard_only usage "$@" || exit 1
if [[ "${SHELL_CLI_ARG_COUNT}" -gt 0 ]]; then
  shell_cli_require_no_args "${SHELL_CLI_ARGS[@]}" || exit 1
fi

case "${OIDC_RECOVERY_FORMAT}" in
  text|json)
    ;;
  *)
    printf 'exercise-kind-oidc-recovery.sh: unsupported OIDC_RECOVERY_FORMAT: %s\n' "${OIDC_RECOVERY_FORMAT}" >&2
    exit 1
    ;;
esac

case "${OIDC_RECOVERY_FORCE_MODE}" in
  nginx-rollout)
    ;;
  *)
    printf 'exercise-kind-oidc-recovery.sh: unsupported OIDC_RECOVERY_FORCE_MODE: %s\n' "${OIDC_RECOVERY_FORCE_MODE}" >&2
    exit 1
    ;;
esac

if json_mode; then
  command -v jq >/dev/null 2>&1 || {
    printf 'exercise-kind-oidc-recovery.sh: jq not found in PATH\n' >&2
    exit 1
  }
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  emit_preview_result
  exit 0
fi

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  if json_mode; then
    emit_preview_result
  else
    usage
    emit_preview_result
  fi
  exit 0
fi

require_cmd kubectl

STEPS_FILE="$(mktemp)"
EVENTS_FILE="$(mktemp)"
RECOVERY_LOG_FILE="$(mktemp)"

cleanup() {
  rm -f "${STEPS_FILE}" "${EVENTS_FILE}" "${RECOVERY_LOG_FILE}"
}
trap cleanup EXIT

RESULT_OK=false
STATUS_CODE="unexpected_failure"
STATUS_GROUP="failure"
SUMMARY=""
FORCED=false
PRE_STATE="unknown"
POST_STATE="unknown"
RECOVERY_EXIT_CODE=0

record_step() {
  printf '%s\t%s\t%s\n' \
    "$(sanitize_record_field "${1}")" \
    "$(sanitize_record_field "${2}")" \
    "$(sanitize_record_field "${3}")" >>"${STEPS_FILE}"
}

record_event() {
  printf '%s\t%s\n' \
    "$(sanitize_record_field "${1}")" \
    "$(sanitize_record_field "${2}")" >>"${EVENTS_FILE}"
}

json_steps() {
  jq -Rn '[inputs | select(length > 0) | split("\t") | {step: .[0], outcome: .[1], message: .[2]}]' <"${STEPS_FILE}"
}

json_events() {
  jq -Rn '[inputs | select(length > 0) | split("\t") | {level: .[0], message: .[1]}]' <"${EVENTS_FILE}"
}

json_line_array() {
  local file_path="${1}"
  jq -Rn '[inputs]' <"${file_path}"
}

emit_result() {
  if json_mode; then
    local steps_json events_json recovery_log_json

    steps_json="$(json_steps)"
    events_json="$(json_events)"
    recovery_log_json="$(json_line_array "${RECOVERY_LOG_FILE}")"

    jq -n \
      --arg summary "${SUMMARY}" \
      --arg status_code "${STATUS_CODE}" \
      --arg status_group "${STATUS_GROUP}" \
      --arg force_mode "${OIDC_RECOVERY_FORCE_MODE}" \
      --arg preflight_state "${PRE_STATE}" \
      --arg postflight_state "${POST_STATE}" \
      --arg recovery_script "${KIND_OIDC_RECOVERY_SCRIPT}" \
      --arg forced_kind "deployment" \
      --arg forced_namespace "${NGINX_GATEWAY_NAMESPACE}" \
      --arg forced_name "${NGINX_GATEWAY_DEPLOY_NAME}" \
      --argjson ok "${RESULT_OK}" \
      --argjson dry_run false \
      --argjson forced "${FORCED}" \
      --argjson recovery_exit_code "${RECOVERY_EXIT_CODE}" \
      --argjson steps "${steps_json}" \
      --argjson events "${events_json}" \
      --argjson recovery_log "${recovery_log_json}" \
      '{
        ok: $ok,
        dry_run: $dry_run,
        status_code: $status_code,
        status_group: $status_group,
        summary: $summary,
        force_mode: $force_mode,
        forced: $forced,
        forced_resource: {
          kind: $forced_kind,
          namespace: $forced_namespace,
          name: $forced_name
        },
        preflight_state: $preflight_state,
        postflight_state: $postflight_state,
        recovery_script: $recovery_script,
        recovery_exit_code: $recovery_exit_code,
        steps: $steps,
        events: $events,
        recovery_log: $recovery_log
      }'
    return 0
  fi

  if [[ "${RESULT_OK}" == true ]]; then
    printf 'OK   %s\n' "${SUMMARY}"
  else
    printf 'FAIL %s\n' "${SUMMARY}" >&2
  fi
}

current_health_state() {
  if kind_oidc_post_restart_dependencies_healthy; then
    printf '%s\n' "healthy"
  else
    printf '%s\n' "degraded"
  fi
}

ok() {
  record_event "ok" "$*"
  if ! json_mode; then
    printf 'OK   %s\n' "$*"
  fi
}

warn() {
  record_event "warn" "$*"
  if ! json_mode; then
    printf 'WARN %s\n' "$*"
  fi
}

fail() {
  record_event "fail" "$*"
  SUMMARY="$*"
  POST_STATE="$(current_health_state)"
  emit_result
  exit 1
}

wait_until_dependencies_degraded() {
  local timeout_seconds="${1}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if ! kind_oidc_post_restart_dependencies_healthy; then
      return 0
    fi
    sleep 1
  done

  return 1
}

force_recycle_deployment_pods() {
  local namespace="${1}"
  local deploy_name="${2}"
  local selector=""
  local pod_names=""
  local pod_name=""

  selector="$(deployment_selector "${namespace}" "${deploy_name}")"
  if [[ -z "${selector}" ]]; then
    fail "could not determine a pod selector for ${namespace}/${deploy_name} while forcing the recovery branch"
  fi

  pod_names="$(
    kubectl -n "${namespace}" get pods \
      -l "${selector}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"
  if [[ -z "${pod_names}" ]]; then
    fail "no pods found for ${namespace}/${deploy_name} while forcing the recovery branch"
  fi

  while IFS= read -r pod_name; do
    [[ -n "${pod_name}" ]] || continue
    ok "recycling ${namespace}/${pod_name} to force the explicit recovery branch"
    kubectl -n "${namespace}" delete pod "${pod_name}" --wait=false >/dev/null 2>&1 || true
  done <<< "${pod_names}"
}

deployment_replicas() {
  local namespace="${1}"
  local deploy_name="${2}"
  local replicas=""

  replicas="$(
    kubectl -n "${namespace}" get deploy "${deploy_name}" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || true
  )"
  if [[ -z "${replicas}" ]]; then
    replicas=1
  fi

  printf '%s\n' "${replicas}"
}

scale_deployment_replicas() {
  local namespace="${1}"
  local deploy_name="${2}"
  local replicas="${3}"

  ok "scaling ${namespace}/${deploy_name} to ${replicas} replicas"
  kubectl -n "${namespace}" scale "deploy/${deploy_name}" --replicas="${replicas}" >/dev/null
}

force_recovery_branch() {
  local initial_wait_seconds=15
  local secondary_wait_seconds=15
  local tertiary_wait_seconds=0
  local original_replicas=1

  case "${OIDC_RECOVERY_FORCE_MODE}" in
    nginx-rollout)
      STATUS_CODE="force_step_failed"
      record_step "force" "running" "restarting ${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME} to force the explicit recovery branch"
      restart_deployment "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" \
        "nginx gateway control plane (${NGINX_GATEWAY_NAMESPACE}/${NGINX_GATEWAY_DEPLOY_NAME})"

      if (( OIDC_RECOVERY_FORCE_WAIT_SECONDS < initial_wait_seconds )); then
        initial_wait_seconds="${OIDC_RECOVERY_FORCE_WAIT_SECONDS}"
      fi

      if ! wait_until_dependencies_degraded "${initial_wait_seconds}"; then
        warn "nginx rollout restart stayed healthy; recycling nginx gateway pods to force an observable degraded window"
        record_step "force" "escalated" "rollout restart stayed healthy; recycling nginx gateway pods to force the explicit recovery branch"
        force_recycle_deployment_pods "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}"
        if (( OIDC_RECOVERY_FORCE_WAIT_SECONDS < (initial_wait_seconds + secondary_wait_seconds) )); then
          secondary_wait_seconds=$((OIDC_RECOVERY_FORCE_WAIT_SECONDS - initial_wait_seconds))
        fi
        if (( secondary_wait_seconds < 1 )); then
          secondary_wait_seconds=1
        fi
        if ! wait_until_dependencies_degraded "${secondary_wait_seconds}"; then
          warn "nginx pod recycle stayed healthy; scaling the controller to zero to force an observable degraded window"
          record_step "force" "escalated" "pod recycle stayed healthy; scaling the nginx gateway controller to zero to force the explicit recovery branch"
          original_replicas="$(deployment_replicas "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}")"
          scale_deployment_replicas "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" 0
          tertiary_wait_seconds=$((OIDC_RECOVERY_FORCE_WAIT_SECONDS - initial_wait_seconds - secondary_wait_seconds))
          if (( tertiary_wait_seconds < 1 )); then
            tertiary_wait_seconds=1
          fi
          if ! wait_until_dependencies_degraded "${tertiary_wait_seconds}"; then
            scale_deployment_replicas "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" "${original_replicas}" || true
            SUMMARY="forced nginx gateway restart, pod recycle, and temporary scale-to-zero did not make the post-restart dependencies unhealthy within ${OIDC_RECOVERY_FORCE_WAIT_SECONDS}s"
            POST_STATE="$(current_health_state)"
            emit_result
            exit 1
          fi
          scale_deployment_replicas "${NGINX_GATEWAY_NAMESPACE}" "${NGINX_GATEWAY_DEPLOY_NAME}" "${original_replicas}"
        fi
      fi
      FORCED=true
      record_step "force" "performed" "forced degradation became observable after the nginx gateway disruption sequence"
      ;;
  esac
}

run_delegated_recovery() {
  local recovery_output=""

  STATUS_CODE="recovery_flow_failed"
  record_step "recovery" "running" "delegating to ${KIND_OIDC_RECOVERY_SCRIPT}"

  set +e
  recovery_output="$(KIND_OIDC_RECOVERY_FORCE_RUN=1 "${KIND_OIDC_RECOVERY_SCRIPT}" --execute 2>&1)"
  RECOVERY_EXIT_CODE=$?
  set -e

  if [[ -n "${recovery_output}" ]]; then
    printf '%s\n' "${recovery_output}" >"${RECOVERY_LOG_FILE}"
    if ! json_mode; then
      printf '%s\n' "${recovery_output}"
    fi
  else
    : >"${RECOVERY_LOG_FILE}"
  fi

  if [[ "${RECOVERY_EXIT_CODE}" -ne 0 ]]; then
    record_step "recovery" "failed" "delegated recovery script exited ${RECOVERY_EXIT_CODE}"
    SUMMARY="delegated recovery script failed with exit ${RECOVERY_EXIT_CODE}"
    POST_STATE="$(current_health_state)"
    emit_result
    exit 1
  fi

  record_step "recovery" "completed" "delegated recovery script completed successfully"
}

PRE_STATE="$(current_health_state)"
record_step "preflight" "${PRE_STATE}" "detected ${PRE_STATE} OIDC runtime dependencies before the exercise"

if [[ "${PRE_STATE}" == "healthy" ]]; then
  force_recovery_branch
else
  record_step "force" "skipped" "cluster already started degraded; skipping additional perturbation"
fi

run_delegated_recovery

POST_STATE="$(current_health_state)"
if [[ "${POST_STATE}" != "healthy" ]]; then
  STATUS_CODE="post_recovery_health_failed"
  SUMMARY="delegated recovery completed but the OIDC runtime dependencies are still degraded"
  record_step "postflight" "failed" "${SUMMARY}"
  emit_result
  exit 1
fi

record_step "postflight" "healthy" "OIDC runtime dependencies are healthy after the delegated recovery"
STATUS_CODE="$(
  if [[ "${FORCED}" == true ]]; then
    printf '%s' "forced_recovery_succeeded"
  else
    printf '%s' "degraded_start_recovery_succeeded"
  fi
)"
STATUS_GROUP="success"
RESULT_OK=true
SUMMARY="controlled OIDC recovery exercise completed successfully"
emit_result
