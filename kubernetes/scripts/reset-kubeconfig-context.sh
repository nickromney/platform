#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [options]

Purpose:
  Prepare a kubeconfig for stack reset, then delete a repo context/cluster/user
  tuple from that kubeconfig.

Options:
  --kubeconfig PATH            Kubeconfig file to mutate
  --context NAME              Context name to remove
  --cluster NAME              Cluster name to remove (default: context)
  --user NAME                 User name to remove (default: context)
  --kubeconfig-helper PATH    manage-kubeconfig.sh path override
  --auto-approve 0|1          Forwarded to prepare-for-reset via env
  --delete-file-if-empty      Remove kubeconfig file if it becomes empty
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

kubeconfig_path=""
context_name=""
cluster_name=""
user_name=""
kubeconfig_helper="${REPO_ROOT}/terraform/kubernetes/scripts/manage-kubeconfig.sh"
auto_approve="0"
delete_file_if_empty=0

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --kubeconfig)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--kubeconfig"
        exit 1
      }
      kubeconfig_path="${2:-}"
      shift 2
      ;;
    --context)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--context"
        exit 1
      }
      context_name="${2:-}"
      shift 2
      ;;
    --cluster)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--cluster"
        exit 1
      }
      cluster_name="${2:-}"
      shift 2
      ;;
    --user)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--user"
        exit 1
      }
      user_name="${2:-}"
      shift 2
      ;;
    --kubeconfig-helper)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--kubeconfig-helper"
        exit 1
      }
      kubeconfig_helper="${2:-}"
      shift 2
      ;;
    --auto-approve)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--auto-approve"
        exit 1
      }
      auto_approve="${2:-}"
      shift 2
      ;;
    --delete-file-if-empty)
      delete_file_if_empty=1
      shift
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would prepare ${kubeconfig_path:-<unspecified>} for reset and delete context ${context_name:-<unspecified>}"

[[ -n "${kubeconfig_path}" ]] || {
  usage >&2
  exit 1
}
[[ -n "${context_name}" ]] || {
  usage >&2
  exit 1
}

cluster_name="${cluster_name:-${context_name}}"
user_name="${user_name:-${context_name}}"

KUBECONFIG_RESET_AUTO_APPROVE="${auto_approve}" \
  "${kubeconfig_helper}" --execute --action prepare-for-reset --kubeconfig "${kubeconfig_path}"

context_found=0
if KUBECONFIG="${kubeconfig_path}" kubectl config get-contexts "${context_name}" >/dev/null 2>&1; then
  context_found=1
fi

delete_args=(
  --execute
  --action delete-context
  --kubeconfig "${kubeconfig_path}"
  --context "${context_name}"
  --cluster "${cluster_name}"
  --user "${user_name}"
)
if [[ "${delete_file_if_empty}" == "1" ]]; then
  delete_args+=(--delete-file-if-empty)
fi

"${kubeconfig_helper}" "${delete_args[@]}"

if [[ "${context_found}" == "1" ]]; then
  exit 0
fi
exit 10
