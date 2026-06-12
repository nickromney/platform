#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

source_kubeconfig=""
target_kubeconfig=""
context_name=""
merge_mode=""
helper="${REPO_ROOT}/terraform/kubernetes/scripts/manage-kubeconfig.sh"
fallback_merge=0
dry_run=0
execute=0

usage() {
  cat <<EOF
Usage: ${0##*/} --source-kubeconfig PATH --target-kubeconfig PATH --context NAME --merge 0|1 [options] [--dry-run] [--execute]

Reconciles a runtime split kubeconfig with the default kubeconfig policy.

Options:
  --helper PATH            manage-kubeconfig helper path.
  --fallback-merge         Merge with kubectl when the helper is unavailable.
$(shell_cli_standard_options)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --execute)
      execute=1
      shift
      ;;
    --shell-entrypoint-descriptor)
      shell_cli_entrypoint_descriptor
      exit 0
      ;;
    --source-kubeconfig)
      source_kubeconfig="$2"
      shift 2
      ;;
    --target-kubeconfig)
      target_kubeconfig="$2"
      shift 2
      ;;
    --context)
      context_name="$2"
      shift 2
      ;;
    --merge)
      merge_mode="$2"
      shift 2
      ;;
    --helper)
      helper="$2"
      shift 2
      ;;
    --fallback-merge)
      fallback_merge=1
      shift
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "${source_kubeconfig}" ] || { echo "ERROR: --source-kubeconfig is required" >&2; exit 2; }
[ -n "${target_kubeconfig}" ] || { echo "ERROR: --target-kubeconfig is required" >&2; exit 2; }
[ -n "${context_name}" ] || { echo "ERROR: --context is required" >&2; exit 2; }
[[ "${merge_mode}" =~ ^(0|1)$ ]] || { echo "ERROR: --merge must be 0 or 1" >&2; exit 2; }

if [[ "${dry_run}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would reconcile ${source_kubeconfig} with ${target_kubeconfig} for ${context_name}"
  exit 0
fi

if [[ "${execute}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would reconcile ${source_kubeconfig} with ${target_kubeconfig} for ${context_name}"
  exit 0
fi

fallback_merge_with_kubectl() {
  local tmp_file

  [ -f "${source_kubeconfig}" ] || return 0
  [ "${source_kubeconfig}" != "${target_kubeconfig}" ] || return 0

  mkdir -p "$(dirname "${target_kubeconfig}")"
  if [ ! -f "${target_kubeconfig}" ]; then
    cp "${source_kubeconfig}" "${target_kubeconfig}"
    kubectl config use-context "${context_name}" --kubeconfig "${target_kubeconfig}" >/dev/null 2>&1 || true
    return 0
  fi

  tmp_file="$(mktemp)"
  if KUBECONFIG="${target_kubeconfig}:${source_kubeconfig}" kubectl config view --flatten >"${tmp_file}"; then
    mv "${tmp_file}" "${target_kubeconfig}"
    chmod 600 "${target_kubeconfig}"
    kubectl config use-context "${context_name}" --kubeconfig "${target_kubeconfig}" >/dev/null 2>&1 || true
  else
    rm -f "${tmp_file}"
    echo "WARN: failed to merge ${source_kubeconfig} into ${target_kubeconfig}" >&2
  fi
}

if [ "${merge_mode}" = "1" ]; then
  if [ -x "${helper}" ]; then
    "${helper}" \
      --execute \
      --action merge \
      --source-kubeconfig "${source_kubeconfig}" \
      --target-kubeconfig "${target_kubeconfig}" \
      --context "${context_name}"
    exit 0
  fi

  if [ "${fallback_merge}" = "1" ]; then
    fallback_merge_with_kubectl
  fi
  exit 0
fi

[ -e "${target_kubeconfig}" ] || exit 0
[ -x "${helper}" ] || exit 0

"${helper}" --execute --action ensure-valid --kubeconfig "${target_kubeconfig}"
"${helper}" \
  --execute \
  --action delete-context \
  --kubeconfig "${target_kubeconfig}" \
  --context "${context_name}" \
  --cluster "${context_name}" \
  --user "${context_name}"
