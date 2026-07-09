#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--stack-dir PATH] [--target PATH]...

Purpose:
  Render the shared platform launchpad dashboard through the Kubernetes stack
  script while keeping runtime Makefiles on one small interface.

Options:
  --stack-dir PATH             Terraform Kubernetes stack root
  --target PATH                Optional launchpad render target to forward
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

stack_dir="${REPO_ROOT}/terraform/kubernetes"
targets=()

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stack-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stack-dir"
        exit 1
      }
      stack_dir="${2:-}"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--target"
        exit 1
      }
      targets+=("--target" "${2:-}")
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

mode_flag="--dry-run"
if [[ "${SHELL_CLI_EXECUTE}" -eq 1 ]]; then
  mode_flag="--execute"
elif [[ "${SHELL_CLI_DRY_RUN}" -eq 0 ]]; then
  usage
fi

if [[ -z "${stack_dir}" ]]; then
  shell_cli_missing_value "$(shell_cli_script_name)" "--stack-dir"
  exit 1
fi

launchpad_script="${stack_dir}/scripts/render-platform-launchpad.sh"
if [[ ! -x "${launchpad_script}" ]]; then
  echo "Missing ${launchpad_script}" >&2
  exit 1
fi

STACK_DIR="${stack_dir}" "${launchpad_script}" "${mode_flag}" ${targets[@]+"${targets[@]}"}
