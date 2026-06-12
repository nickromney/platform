#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

variant_json=""
stage=""
make_dir=""

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute] --variant-json PATH --stage STAGE --make-dir DIR

Runs planned post-apply verification Make targets read from stdin.

Options:
  --variant-json PATH
    Variant contract file under kubernetes/variants/.
  --stage STAGE
    Selected stage number.
  --make-dir DIR
    Kubernetes variant Makefile directory.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  printf 'run-post-apply-verification.sh: %s\n' "$*" >&2
  exit 1
}

run_make_step() {
  local step="$1"
  shift
  # Keep the planned-step stream on stdin away from make recipes (ssh,
  # limactl, etc. would otherwise consume the remaining plan lines).
  make -C "${make_dir}" "${step}" "$@" </dev/null
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
    --make-dir)
      [[ "$#" -ge 2 ]] || fail "missing value for --make-dir"
      make_dir="$2"
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
case "${stage}" in
  ''|*[!0-9]*) fail "stage must be numeric: ${stage}" ;;
esac
[[ -n "${make_dir}" ]] || fail "missing --make-dir"
[[ -d "${make_dir}" ]] || fail "make directory not found: ${make_dir}"

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
    shell_cli_print_dry_run_summary "would run post-apply verification for stage ${stage}"
  else
    usage
    shell_cli_print_dry_run_summary "would run post-apply verification for stage ${stage}"
  fi
  exit 0
fi

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"

variant_id="$(jq -r '.id // ""' "${variant_json}")"
[[ -n "${variant_id}" ]] || fail "variant contract is missing id"

while IFS= read -r post_apply_step; do
  [[ -n "${post_apply_step}" ]] || continue
  case "${post_apply_step}" in
    configure-k3s-apiserver-oidc)
      case "${variant_id}" in
        lima) run_make_step "${post_apply_step}" ;;
        slicer) run_make_step "${post_apply_step}" "STAGE=${stage}" ;;
        *) fail "post-apply step ${post_apply_step} is not supported for ${variant_id}" ;;
      esac
      ;;
    check-health|check-gateway-urls|check-sso-e2e)
      run_make_step "${post_apply_step}" "STAGE=${stage}"
      ;;
    *)
      fail "Unknown post-apply verification step: ${post_apply_step}"
      ;;
  esac
done
