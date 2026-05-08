#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${DEFAULT_MODULE_DIR}/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

MODULE_DIR="${TOFU_TEST_MODULE_DIR:-${STACK_DIR:-${DEFAULT_MODULE_DIR}}}"
TEST_FILTER="${TOFU_TEST_FILTER:-}"
TIMEOUT_SECONDS="${TOFU_TEST_TIMEOUT_SECONDS:-180}"
TERRAFORM_BINARY="${TOFU_TEST_BINARY:-${TERRAFORM_TEST_BINARY:-tofu}}"
EXTRA_VALIDATION="${TERRAFORM_TEST_EXTRA_VALIDATION:-${TOFU_TEST_EXTRA_VALIDATION:-${TERRAFORM_TEST_1_15_VALIDATION:-auto}}}"
JSON_LOG_DIR="${TERRAFORM_TEST_JSON_LOG_DIR:-${TOFU_TEST_JSON_LOG_DIR:-}}"
TERRAFORM_VERSION_LINE_READY=0
TERRAFORM_VERSION_LINE=""

usage() {
  cat <<EOF
Usage: ${0##*/} [--module-dir PATH] [--filter FILTER] [--timeout-seconds SECONDS] [--binary NAME] [--dry-run] [--execute]

Runs Terraform-compatible tests for the Kubernetes Terraform module with an
explicit init step and a hard wall-clock bound.

Options:
  --module-dir PATH          Terraform/OpenTofu module directory (default: ${DEFAULT_MODULE_DIR})
  --filter FILTER            Optional tofu test filter passed as -filter=FILTER
  --timeout-seconds SECONDS  Timeout for each tofu command (default: ${TIMEOUT_SECONDS})
  --binary NAME              Terraform-compatible CLI binary (default: ${TERRAFORM_BINARY})
  --extra-validation auto|on|off
                             Run supported validate-before-test checks (default: ${EXTRA_VALIDATION})
  --terraform-1-15-validation auto|on|off
                             Backward-compatible alias for --extra-validation
  --json-log-dir PATH        Capture OpenTofu 1.12+ JSON logs with -json-into
$(shell_cli_standard_options)
EOF
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
      --module-dir|--stack-dir)
        if [[ $# -lt 2 ]]; then
          shell_cli_missing_value "${script_name}" "$1"
          return 1
        fi
        MODULE_DIR="$2"
        shift 2
        ;;
      --filter)
        if [[ $# -lt 2 ]]; then
          shell_cli_missing_value "${script_name}" "$1"
          return 1
        fi
        TEST_FILTER="$2"
        shift 2
        ;;
      --timeout-seconds)
        if [[ $# -lt 2 ]]; then
          shell_cli_missing_value "${script_name}" "$1"
          return 1
        fi
        TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --binary)
        if [[ $# -lt 2 ]]; then
          shell_cli_missing_value "${script_name}" "$1"
          return 1
        fi
        TERRAFORM_BINARY="$2"
        shift 2
        ;;
      --extra-validation|--terraform-1-15-validation)
        if [[ $# -lt 2 ]]; then
          shell_cli_missing_value "${script_name}" "$1"
          return 1
        fi
        EXTRA_VALIDATION="$2"
        shift 2
        ;;
      --json-log-dir)
        if [[ $# -lt 2 ]]; then
          shell_cli_missing_value "${script_name}" "$1"
          return 1
        fi
        JSON_LOG_DIR="$2"
        shift 2
        ;;
      --)
        shift
        if [[ $# -gt 0 ]]; then
          shell_cli_unexpected_arg "${script_name}" "$1"
          return 1
        fi
        ;;
      -*)
        shell_cli_unknown_flag "${script_name}" "$1"
        return 1
        ;;
      *)
        shell_cli_unexpected_arg "${script_name}" "$1"
        return 1
        ;;
    esac
  done
}

validate_args() {
  if [[ ! -d "${MODULE_DIR}" ]]; then
    printf 'OpenTofu module directory not found: %s\n' "${MODULE_DIR}" >&2
    return 1
  fi

  case "${TIMEOUT_SECONDS}" in
    ''|*[!0-9]*)
      printf 'timeout seconds must be a positive integer: %s\n' "${TIMEOUT_SECONDS}" >&2
      return 1
      ;;
    0)
      printf 'timeout seconds must be greater than zero\n' >&2
      return 1
      ;;
  esac

  if [[ -z "${TERRAFORM_BINARY}" ]]; then
    printf 'Terraform-compatible CLI binary must not be empty\n' >&2
    return 1
  fi

  case "${EXTRA_VALIDATION}" in
    auto|on|off) ;;
    *)
      printf 'extra validation mode must be one of: auto, on, off\n' >&2
      return 1
      ;;
  esac
}

preview() {
  local summary

  summary="would run ${TERRAFORM_BINARY} init -backend=false -input=false and bounded ${TERRAFORM_BINARY} test in ${MODULE_DIR}"
  if [[ -n "${TEST_FILTER}" ]]; then
    summary="${summary} -filter=${TEST_FILTER}"
  fi
  if [[ "${EXTRA_VALIDATION}" != "off" ]]; then
    summary="${summary}; extra validation mode=${EXTRA_VALIDATION}"
  fi
  if [[ -n "${JSON_LOG_DIR}" ]]; then
    summary="${summary}; OpenTofu JSON log dir=${JSON_LOG_DIR}"
  fi
  shell_cli_print_dry_run_summary "${summary}"
}

configure_split_kubeconfig_defaults() {
  if [[ -z "${KUBECONFIG:-}" && -n "${KUBECONFIG_PATH:-}" ]]; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
  fi

  if [[ -z "${TF_VAR_kubeconfig_path:-}" && -n "${KUBECONFIG_PATH:-}" ]]; then
    export TF_VAR_kubeconfig_path="${KUBECONFIG_PATH}"
  fi

  if [[ -z "${TF_VAR_kubeconfig_context:-}" && -n "${KUBECONFIG_CONTEXT:-}" ]]; then
    export TF_VAR_kubeconfig_context="${KUBECONFIG_CONTEXT}"
  fi
}

list_tofu_processes() {
  pgrep -af 'tofu|terraform-provider|terraform' 2>/dev/null || true
}

kill_process_tree() {
  local pid="$1"

  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -P "${pid}" 2>/dev/null || true
  fi
  kill -TERM "${pid}" 2>/dev/null || true
  sleep 2
  if command -v pkill >/dev/null 2>&1; then
    pkill -KILL -P "${pid}" 2>/dev/null || true
  fi
  kill -KILL "${pid}" 2>/dev/null || true
}

run_bounded_command() {
  local label="$1"
  local output_file pid start elapsed rc

  shift
  output_file="$(mktemp "${TMPDIR:-/tmp}/opentofu-test-output.XXXXXX")"

  "$@" >"${output_file}" 2>&1 &
  pid=$!
  start="$(date +%s)"

  while kill -0 "${pid}" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [[ "${elapsed}" -ge "${TIMEOUT_SECONDS}" ]]; then
      printf 'Timed out after %ss: %s\n' "${TIMEOUT_SECONDS}" "${label}" >&2
      printf 'Terraform/OpenTofu provider processes at timeout:\n' >&2
      list_tofu_processes >&2
      kill_process_tree "${pid}"
      wait "${pid}" 2>/dev/null || true
      cat "${output_file}" >&2
      rm -f "${output_file}"
      return 124
    fi

    sleep 1
  done

  rc=1
  if wait "${pid}"; then
    rc=0
  else
    rc=$?
  fi

  cat "${output_file}"
  rm -f "${output_file}"
  return "${rc}"
}

terraform_cli_version_line() {
  if [[ "${TERRAFORM_VERSION_LINE_READY}" -eq 0 ]]; then
    TERRAFORM_VERSION_LINE="$("${TERRAFORM_BINARY}" version 2>/dev/null | sed -n '1p' || true)"
    TERRAFORM_VERSION_LINE_READY=1
  fi
  printf '%s\n' "${TERRAFORM_VERSION_LINE}"
}

terraform_cli_at_least() {
  local product="$1"
  local minimum_major="$2"
  local minimum_minor="$3"
  local version_output=""
  local major=""
  local minor=""

  version_output="$(terraform_cli_version_line)"
  if [[ ! "${version_output}" =~ ^${product}[[:space:]]+v([0-9]+)\.([0-9]+)(\.|$|-|\+) ]]; then
    return 1
  fi

  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"

  if [[ "${major}" -gt "${minimum_major}" ]]; then
    return 0
  fi
  if [[ "${major}" -eq "${minimum_major}" && "${minor}" -ge "${minimum_minor}" ]]; then
    return 0
  fi
  return 1
}

terraform_cli_is_terraform_at_least() {
  terraform_cli_at_least "Terraform" "$1" "$2"
}

terraform_cli_is_opentofu_at_least() {
  terraform_cli_at_least "OpenTofu" "$1" "$2"
}

extra_validation_supported() {
  case "${EXTRA_VALIDATION}" in
    off)
      return 1
      ;;
    on)
      return 0
      ;;
  esac

  terraform_cli_is_terraform_at_least 1 15 || terraform_cli_is_opentofu_at_least 1 12
}

opentofu_json_logs_supported() {
  [[ -n "${JSON_LOG_DIR}" ]] || return 1
  terraform_cli_is_opentofu_at_least 1 12
}

json_log_arg_for() {
  local command_name="$1"

  if opentofu_json_logs_supported; then
    mkdir -p "${JSON_LOG_DIR}"
    printf -- '-json-into=%s/%s.jsonl' "${JSON_LOG_DIR}" "${command_name}"
  fi
}

run_opentofu_tests() {
  local init_args validate_args test_args json_log_arg

  command -v "${TERRAFORM_BINARY}" >/dev/null 2>&1 || { printf '%s not found in PATH\n' "${TERRAFORM_BINARY}" >&2; return 127; }
  configure_split_kubeconfig_defaults

  init_args=("${TERRAFORM_BINARY}" "-chdir=${MODULE_DIR}" init -backend=false -input=false)
  json_log_arg="$(json_log_arg_for init)"
  if [[ -n "${json_log_arg}" ]]; then
    init_args+=("${json_log_arg}")
  fi

  run_bounded_command "${TERRAFORM_BINARY} init -backend=false -input=false" "${init_args[@]}"

  if extra_validation_supported; then
    validate_args=("${TERRAFORM_BINARY}" "-chdir=${MODULE_DIR}" validate)
    json_log_arg="$(json_log_arg_for validate)"
    if [[ -n "${json_log_arg}" ]]; then
      validate_args+=("${json_log_arg}")
    fi
    run_bounded_command "${TERRAFORM_BINARY} validate" "${validate_args[@]}"
  fi

  test_args=("${TERRAFORM_BINARY}" "-chdir=${MODULE_DIR}" test)
  if [[ -n "${TEST_FILTER}" ]]; then
    test_args+=("-filter=${TEST_FILTER}")
  fi
  json_log_arg="$(json_log_arg_for test)"
  if [[ -n "${json_log_arg}" ]]; then
    test_args+=("${json_log_arg}")
  fi

  run_bounded_command "${TERRAFORM_BINARY} test" "${test_args[@]}"
}

main() {
  parse_args "$@" || exit 1
  validate_args || exit 1
  shell_cli_maybe_execute_or_preview usage preview
  run_opentofu_tests
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
