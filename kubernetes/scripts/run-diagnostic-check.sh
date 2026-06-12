#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

variant_json=""
action=""
stage=""
stack_dir="${REPO_ROOT}/terraform/kubernetes"
var_files=()

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute] --variant-json PATH --action ACTION --stage STAGE [--stack-dir PATH] [--var-file PATH ...]

Runs a Kubernetes diagnostic through the shared variant contract dispatch layer.

Options:
  --variant-json PATH
    Variant contract file under kubernetes/variants/.
  --action ACTION
    Diagnostic action to run. Supported actions: check-health, show-urls.
  --stage STAGE
    Selected stage number.
  --stack-dir PATH
    Terraform Kubernetes stack directory. Defaults to terraform/kubernetes.
  --var-file PATH
    Optional OpenTofu/Terraform tfvars file. Repeat to preserve precedence.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  printf 'run-diagnostic-check.sh: %s\n' "$*" >&2
  exit 1
}

expand_home() {
  local path="$1"

  # shellcheck disable=SC2088 # Intentional literal ~/ prefix from variant contracts.
  case "${path}" in
    "~")
      printf '%s\n' "${HOME}"
      ;;
    "~/"*)
      printf '%s/%s\n' "${HOME}" "${path#\~/}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

script_name="$(shell_cli_script_name)"
shell_cli_init_standard_flags
while [[ "$#" -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --variant-json)
      [[ "$#" -ge 2 ]] || fail "missing value for --variant-json"
      variant_json="$2"
      shift 2
      ;;
    --action)
      [[ "$#" -ge 2 ]] || fail "missing value for --action"
      action="$2"
      shift 2
      ;;
    --stage)
      [[ "$#" -ge 2 ]] || fail "missing value for --stage"
      stage="$2"
      shift 2
      ;;
    --stack-dir)
      [[ "$#" -ge 2 ]] || fail "missing value for --stack-dir"
      stack_dir="$2"
      shift 2
      ;;
    --var-file)
      [[ "$#" -ge 2 ]] || fail "missing value for --var-file"
      var_files+=("$2")
      shift 2
      ;;
    *)
      if [[ "$1" == -* ]]; then
        shell_cli_unknown_flag "${script_name}" "$1"
      else
        shell_cli_unexpected_arg "${script_name}" "$1"
      fi
      exit 1
      ;;
  esac
done

[[ -n "${variant_json}" ]] || fail "missing --variant-json"
[[ -f "${variant_json}" ]] || fail "variant contract not found: ${variant_json}"
[[ -n "${action}" ]] || fail "missing --action"
[[ -n "${stage}" ]] || fail "missing --stage"

case "${action}" in
  check-health|show-urls)
    ;;
  *)
    fail "unsupported diagnostic action: ${action}"
    ;;
esac

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
    shell_cli_print_dry_run_summary "would run ${action} diagnostic for stage ${stage}"
  else
    usage
    shell_cli_print_dry_run_summary "would run ${action} diagnostic for stage ${stage}"
  fi
  exit 0
fi

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"

kubeconfig_path="$(jq -r '.cluster_access.kubeconfig_path // ""' "${variant_json}")"
kubeconfig_context="$(jq -r '.cluster_access.kubeconfig_context // ""' "${variant_json}")"
host_access_mode="$(jq -r '.host_access_path.mode // ""' "${variant_json}")"
[[ -n "${kubeconfig_path}" ]] || fail "variant contract is missing cluster_access.kubeconfig_path"
[[ -n "${host_access_mode}" ]] || fail "variant contract is missing host_access_path.mode"
kubeconfig_path="$(expand_home "${kubeconfig_path}")"

args=()
for var_file in "${var_files[@]}"; do
  [[ -n "${var_file}" ]] || continue
  args+=(--var-file "${var_file}")
done

case "${action}" in
  check-health)
    mode_flag="--execute"
    if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
      mode_flag="--dry-run"
    fi
    KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-${kubeconfig_context}}" \
    KUBECONFIG="${KUBECONFIG:-${kubeconfig_path}}" \
      "${stack_dir}/scripts/check-cluster-health.sh" "${mode_flag}" "${args[@]}"
    ;;
  show-urls)
    mode_flag="--execute"
    if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
      mode_flag="--dry-run"
    fi
    KUBECONFIG_CONTEXT="${KUBECONFIG_CONTEXT:-${kubeconfig_context}}" \
    KUBECONFIG="${KUBECONFIG:-${kubeconfig_path}}" \
      "${stack_dir}/scripts/check-cluster-health.sh" "${mode_flag}" --show-urls "${args[@]}"
    ;;
esac
