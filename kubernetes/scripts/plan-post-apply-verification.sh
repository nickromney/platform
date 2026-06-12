#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

variant_json=""
stage=""
var_files=()

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute] --variant-json PATH --stage STAGE [--var-file PATH ...]

Prints ordered post-apply verification Make targets for a Kubernetes variant.

Options:
  --variant-json PATH
    Variant contract file under kubernetes/variants/.
  --stage STAGE
    Selected stage number.
  --var-file PATH
    Optional OpenTofu/Terraform tfvars file. Repeat to preserve precedence.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  printf 'plan-post-apply-verification.sh: %s\n' "$*" >&2
  exit 1
}

resolve_tfvar() {
  local key="$1"
  local default_value="$2"
  "${REPO_ROOT}/kubernetes/scripts/resolve-tfvar-value.sh" --execute "${key}" "${default_value}" "${var_files[@]}"
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
    --stage)
      [[ "$#" -ge 2 ]] || fail "missing value for --stage"
      stage="$2"
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
[[ -n "${stage}" ]] || fail "missing --stage"
[[ "${stage}" =~ ^[0-9]+$ ]] || fail "stage must be numeric: ${stage}"

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
    shell_cli_print_dry_run_summary "would plan post-apply verification for stage ${stage}"
  else
    usage
    shell_cli_print_dry_run_summary "would plan post-apply verification for stage ${stage}"
  fi
  exit 0
fi

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"

variant_id="$(jq -r '.id // ""' "${variant_json}")"
[[ -n "${variant_id}" ]] || fail "variant contract is missing id"

stage_num=$((10#${stage}))
enable_gateway_tls="$(resolve_tfvar enable_gateway_tls false)"
enable_headlamp="$(resolve_tfvar enable_headlamp false)"
enable_sso="$(resolve_tfvar enable_sso false)"

case "${variant_id}" in
  kind)
    if [[ "${stage_num}" -ge 800 && "${enable_gateway_tls}" = "true" ]]; then
      printf '%s\n' check-health check-gateway-urls
      if [[ "${stage_num}" -ge 900 && "${enable_headlamp}" = "true" && "${enable_sso}" = "true" ]]; then
        printf '%s\n' check-sso-e2e
      fi
    fi
    ;;
  lima|slicer)
    if [[ "${stage_num}" -ge 900 && "${enable_gateway_tls}" = "true" && "${enable_headlamp}" = "true" && "${enable_sso}" = "true" ]]; then
      printf '%s\n' configure-k3s-apiserver-oidc check-health check-gateway-urls check-sso-e2e
    fi
    ;;
  *)
    fail "unsupported variant id: ${variant_id}"
    ;;
esac
