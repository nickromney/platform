#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

OIDC_RECOVERY_FORMAT="${OIDC_RECOVERY_FORMAT:-text}"
OIDC_RECOVERY_FORCE_MODE="${OIDC_RECOVERY_FORCE_MODE:-k3s-restart}"
OIDC_RECOVERY_FORCE_WAIT_SECONDS="${OIDC_RECOVERY_FORCE_WAIT_SECONDS:-60}"
OIDC_RECOVERY_READY_WAIT_SECONDS="${OIDC_RECOVERY_READY_WAIT_SECONDS:-180}"
OIDC_RECOVERY_GATEWAY_WAIT_SECONDS="${OIDC_RECOVERY_GATEWAY_WAIT_SECONDS:-180}"
OIDC_RECOVERY_ISSUER_WAIT_SECONDS="${OIDC_RECOVERY_ISSUER_WAIT_SECONDS:-180}"
LIMA_OIDC_CONFIGURE_SCRIPT="${LIMA_OIDC_CONFIGURE_SCRIPT:-${SCRIPT_DIR}/configure-k3s-apiserver-oidc.sh}"

LIMA_NODE_NAME="${LIMA_NODE_NAME:-k3s-node-1}"
PLATFORM_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN:-127.0.0.1.sslip.io}"
PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_ADMIN_BASE_DOMAIN:-${PLATFORM_BASE_DOMAIN}}"
DEX_HOST="${DEX_HOST:-dex.${PLATFORM_ADMIN_BASE_DOMAIN}}"
OIDC_ISSUER_URL="${OIDC_ISSUER_URL:-https://${DEX_HOST}/dex}"
MKCERT_CA_DEST="${MKCERT_CA_DEST:-/etc/rancher/k3s/mkcert-rootCA.pem}"
PLATFORM_GATEWAY_NAMESPACE="${PLATFORM_GATEWAY_NAMESPACE:-platform-gateway}"
PLATFORM_GATEWAY_NAME="${PLATFORM_GATEWAY_NAME:-platform-gateway}"

json_mode() {
  [ "${OIDC_RECOVERY_FORMAT}" = "json" ]
}

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Runs a controlled Lima OIDC recovery drill: converge the k3s apiserver OIDC
configuration, force a k3s restart, observe the temporary API outage, and
verify that the API, gateway, and in-VM OIDC issuer reachability recover.

Environment:
  OIDC_RECOVERY_FORMAT=text|json
    Output format. Json mode emits one machine-readable object on stdout.
  OIDC_RECOVERY_FORCE_MODE=k3s-restart
    Controlled perturbation mode used to force the Lima OIDC restart path.
  LIMA_OIDC_CONFIGURE_SCRIPT=/abs/path/script.sh
    Override the delegated configure script.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

sanitize_record_field() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   '
}

preview_summary="would exercise the Lima k3s OIDC restart path and verify recovery"

emit_preview_result() {
  if json_mode; then
    jq -n \
      --arg force_mode "${OIDC_RECOVERY_FORCE_MODE}" \
      --arg configure_script "${LIMA_OIDC_CONFIGURE_SCRIPT}" \
      --arg summary "${preview_summary}" \
      '{
        ok: true,
        dry_run: true,
        status_code: "dry_run",
        status_group: "preview",
        summary: $summary,
        force_mode: $force_mode,
        configure_script: $configure_script
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
    printf 'exercise-k3s-oidc-recovery.sh: unsupported OIDC_RECOVERY_FORMAT: %s\n' "${OIDC_RECOVERY_FORMAT}" >&2
    exit 1
    ;;
esac

case "${OIDC_RECOVERY_FORCE_MODE}" in
  k3s-restart)
    ;;
  *)
    printf 'exercise-k3s-oidc-recovery.sh: unsupported OIDC_RECOVERY_FORCE_MODE: %s\n' "${OIDC_RECOVERY_FORCE_MODE}" >&2
    exit 1
    ;;
esac

if json_mode; then
  command -v jq >/dev/null 2>&1 || {
    printf 'exercise-k3s-oidc-recovery.sh: jq not found in PATH\n' >&2
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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'exercise-k3s-oidc-recovery.sh: %s not found in PATH\n' "$1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd limactl

STEPS_FILE="$(mktemp)"
EVENTS_FILE="$(mktemp)"
CONFIGURE_LOG_FILE="$(mktemp)"

cleanup() {
  rm -f "${STEPS_FILE}" "${EVENTS_FILE}" "${CONFIGURE_LOG_FILE}"
}
trap cleanup EXIT

RESULT_OK=false
STATUS_CODE="unexpected_failure"
STATUS_GROUP="failure"
SUMMARY=""
PRE_STATE="unknown"
POST_STATE="unknown"
FORCED=false
DEGRADED_OBSERVED=false
CONFIGURE_EXIT_CODE=0

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
    local steps_json events_json configure_log_json

    steps_json="$(json_steps)"
    events_json="$(json_events)"
    configure_log_json="$(json_line_array "${CONFIGURE_LOG_FILE}")"

    jq -n \
      --arg summary "${SUMMARY}" \
      --arg status_code "${STATUS_CODE}" \
      --arg status_group "${STATUS_GROUP}" \
      --arg force_mode "${OIDC_RECOVERY_FORCE_MODE}" \
      --arg preflight_state "${PRE_STATE}" \
      --arg postflight_state "${POST_STATE}" \
      --arg configure_script "${LIMA_OIDC_CONFIGURE_SCRIPT}" \
      --arg forced_kind "service" \
      --arg forced_name "k3s" \
      --arg forced_node "${LIMA_NODE_NAME}" \
      --argjson ok "${RESULT_OK}" \
      --argjson dry_run false \
      --argjson forced "${FORCED}" \
      --argjson degraded_observed "${DEGRADED_OBSERVED}" \
      --argjson configure_exit_code "${CONFIGURE_EXIT_CODE}" \
      --argjson steps "${steps_json}" \
      --argjson events "${events_json}" \
      --argjson configure_log "${configure_log_json}" \
      '{
        ok: $ok,
        dry_run: $dry_run,
        status_code: $status_code,
        status_group: $status_group,
        summary: $summary,
        force_mode: $force_mode,
        forced: $forced,
        degraded_observed: $degraded_observed,
        forced_resource: {
          kind: $forced_kind,
          node: $forced_node,
          name: $forced_name
        },
        preflight_state: $preflight_state,
        postflight_state: $postflight_state,
        configure_script: $configure_script,
        configure_exit_code: $configure_exit_code,
        steps: $steps,
        events: $events,
        configure_log: $configure_log
      }'
    return 0
  fi

  if [[ "${RESULT_OK}" == true ]]; then
    printf 'OK   %s\n' "${SUMMARY}"
  else
    printf 'FAIL %s\n' "${SUMMARY}" >&2
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
  POST_STATE="$(current_state)"
  emit_result
  exit 1
}

lima_exec() {
  local node_name="$1"
  shift
  limactl shell "${node_name}" -- "$@"
}

oidc_issuer_reachable_from_vm_once() {
  set +e
  lima_exec "${LIMA_NODE_NAME}" sudo curl -fsS --max-time 5 --cacert "${MKCERT_CA_DEST}" \
    "${OIDC_ISSUER_URL}/.well-known/openid-configuration" >/dev/null 2>&1
  local status=$?
  set -e
  return "${status}"
}

gateway_programmed_once() {
  local programmed="" accepted=""

  programmed="$(
    kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" \
      -o jsonpath='{range .status.conditions[?(@.type=="Programmed")]}{.status}{end}' 2>/dev/null || true
  )"
  accepted="$(
    kubectl -n "${PLATFORM_GATEWAY_NAMESPACE}" get gateway "${PLATFORM_GATEWAY_NAME}" \
      -o jsonpath='{range .status.conditions[?(@.type=="Accepted")]}{.status}{end}' 2>/dev/null || true
  )"

  [[ "${programmed}" == "True" && "${accepted}" == "True" ]]
}

kube_apiserver_ready_once() {
  local ready_status=0
  set +e
  kubectl get --raw='/readyz' --request-timeout=5s >/dev/null 2>&1
  ready_status=$?
  set -e

  [[ "${ready_status}" -eq 0 ]]
}

preflight_state() {
  if kube_apiserver_ready_once; then
    printf '%s\n' "healthy"
  else
    printf '%s\n' "degraded"
  fi
}

current_state() {
  if ! kube_apiserver_ready_once; then
    printf '%s\n' "degraded"
    return 0
  fi

  if ! gateway_programmed_once; then
    printf '%s\n' "degraded"
    return 0
  fi

  if ! oidc_issuer_reachable_from_vm_once; then
    printf '%s\n' "degraded"
    return 0
  fi

  printf '%s\n' "healthy"
}

wait_for_kube_apiserver_unavailable() {
  local timeout_seconds="${1}"
  local deadline=$((SECONDS + timeout_seconds))
  local ready_status=0

  while (( SECONDS < deadline )); do
    set +e
    kubectl get --raw='/readyz' --request-timeout=5s >/dev/null 2>&1
    ready_status=$?
    set -e
    if [[ "${ready_status}" -ne 0 ]]; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_kube_apiserver_ready() {
  local timeout_seconds="${1}"
  local required_consecutive_successes="${2:-3}"
  local deadline=$((SECONDS + timeout_seconds))
  local consecutive_successes=0
  local ready_status=0

  while (( SECONDS < deadline )); do
    set +e
    kubectl get --raw='/readyz' --request-timeout=5s >/dev/null 2>&1
    ready_status=$?
    set -e

    if [[ "${ready_status}" -eq 0 ]]; then
      consecutive_successes=$((consecutive_successes + 1))
      if (( consecutive_successes >= required_consecutive_successes )); then
        return 0
      fi
      sleep 1
      continue
    fi

    consecutive_successes=0
    sleep 2
  done

  return 1
}

wait_for_gateway_programmed() {
  local timeout_seconds="${1}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if gateway_programmed_once; then
      return 0
    fi
    sleep 2
  done

  return 1
}

wait_for_oidc_issuer_from_vm() {
  local timeout_seconds="${1}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    if oidc_issuer_reachable_from_vm_once; then
      return 0
    fi
    sleep 2
  done

  return 1
}

run_configure_step() {
  local configure_output=""

  STATUS_CODE="configure_step_failed"
  record_step "configure" "running" "delegating to ${LIMA_OIDC_CONFIGURE_SCRIPT}"

  set +e
  configure_output="$("${LIMA_OIDC_CONFIGURE_SCRIPT}" --execute 2>&1)"
  CONFIGURE_EXIT_CODE=$?
  set -e

  if [[ -n "${configure_output}" ]]; then
    printf '%s\n' "${configure_output}" >"${CONFIGURE_LOG_FILE}"
    if ! json_mode; then
      printf '%s\n' "${configure_output}"
    fi
  else
    : >"${CONFIGURE_LOG_FILE}"
  fi

  if [[ "${CONFIGURE_EXIT_CODE}" -ne 0 ]]; then
    record_step "configure" "failed" "configure script exited ${CONFIGURE_EXIT_CODE}"
    SUMMARY="delegated configure script failed with exit ${CONFIGURE_EXIT_CODE}"
    POST_STATE="$(current_state)"
    emit_result
    exit 1
  fi

  record_step "configure" "completed" "delegated configure script completed successfully"
}

force_restart() {
  local restart_output=""

  STATUS_CODE="force_step_failed"
  record_step "force" "running" "restarting k3s on ${LIMA_NODE_NAME} to force the Lima OIDC recovery path"

  set +e
  restart_output="$(lima_exec "${LIMA_NODE_NAME}" sudo systemctl restart k3s 2>&1)"
  local restart_status=$?
  set -e

  if [[ -n "${restart_output}" ]] && ! json_mode; then
    printf '%s\n' "${restart_output}"
  fi

  if [[ "${restart_status}" -ne 0 ]]; then
    SUMMARY="forced k3s restart failed with exit ${restart_status}"
    record_step "force" "failed" "${SUMMARY}"
    POST_STATE="$(current_state)"
    emit_result
    exit 1
  fi

  FORCED=true
  ok "restarted k3s on ${LIMA_NODE_NAME}"

  if ! wait_for_kube_apiserver_unavailable "${OIDC_RECOVERY_FORCE_WAIT_SECONDS}"; then
    SUMMARY="forced k3s restart did not produce an observable kube-apiserver outage within ${OIDC_RECOVERY_FORCE_WAIT_SECONDS}s"
    POST_STATE="$(current_state)"
    emit_result
    exit 1
  fi

  DEGRADED_OBSERVED=true
  record_step "force" "performed" "observed kube-apiserver unavailability after the forced k3s restart"
}

run_recovery_checks() {
  STATUS_CODE="post_restart_recovery_failed"
  record_step "recovery" "running" "waiting for the k3s apiserver, gateway, and in-VM issuer reachability to recover"

  if ! wait_for_kube_apiserver_ready "${OIDC_RECOVERY_READY_WAIT_SECONDS}" 3; then
    SUMMARY="kube-apiserver did not recover within ${OIDC_RECOVERY_READY_WAIT_SECONDS}s after the forced k3s restart"
    record_step "recovery" "failed" "${SUMMARY}"
    POST_STATE="$(current_state)"
    emit_result
    exit 1
  fi

  if ! wait_for_gateway_programmed "${OIDC_RECOVERY_GATEWAY_WAIT_SECONDS}"; then
    SUMMARY="gateway ${PLATFORM_GATEWAY_NAMESPACE}/${PLATFORM_GATEWAY_NAME} did not recover within ${OIDC_RECOVERY_GATEWAY_WAIT_SECONDS}s after the forced k3s restart"
    record_step "recovery" "failed" "${SUMMARY}"
    POST_STATE="$(current_state)"
    emit_result
    exit 1
  fi

  if ! wait_for_oidc_issuer_from_vm "${OIDC_RECOVERY_ISSUER_WAIT_SECONDS}"; then
    SUMMARY="OIDC issuer ${OIDC_ISSUER_URL} was not reachable from ${LIMA_NODE_NAME} within ${OIDC_RECOVERY_ISSUER_WAIT_SECONDS}s after the forced k3s restart"
    record_step "recovery" "failed" "${SUMMARY}"
    POST_STATE="$(current_state)"
    emit_result
    exit 1
  fi

  record_step "recovery" "completed" "k3s apiserver, gateway, and in-VM issuer reachability recovered after the forced restart"
}

run_configure_step

PRE_STATE="$(preflight_state)"
record_step "preflight" "${PRE_STATE}" "detected ${PRE_STATE} Lima OIDC runtime dependencies before the forced restart"

if [[ "${PRE_STATE}" != "healthy" ]]; then
  STATUS_CODE="preflight_not_ready"
  SUMMARY="kube-apiserver is not healthy after the delegated configure step"
  emit_result
  exit 1
fi

force_restart
run_recovery_checks

POST_STATE="$(current_state)"
if [[ "${POST_STATE}" != "healthy" ]]; then
  STATUS_CODE="postflight_not_ready"
  SUMMARY="forced k3s restart completed but the Lima OIDC runtime dependencies are still degraded"
  record_step "postflight" "failed" "${SUMMARY}"
  emit_result
  exit 1
fi

record_step "postflight" "healthy" "Lima OIDC runtime dependencies are healthy after the forced restart drill"
STATUS_CODE="forced_k3s_restart_recovered"
STATUS_GROUP="success"
RESULT_OK=true
SUMMARY="controlled Lima OIDC restart drill completed successfully"
emit_result
