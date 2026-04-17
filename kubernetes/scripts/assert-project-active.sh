#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT:-${REPO_ROOT}/scripts/platform-status.sh}"
EXPECTED_PROJECT_PATH="${EXPECTED_PROJECT_PATH:-}"
EXPECTED_PROJECT_LABEL="${EXPECTED_PROJECT_LABEL:-${EXPECTED_PROJECT_PATH:-requested project}}"
kubeconfig_path="${KUBECONFIG_PATH:-${KUBECONFIG:-}}"
kubeconfig_context="${KUBECONFIG_CONTEXT:-}"

usage() {
  cat <<EOF
Usage: assert-project-active.sh [--dry-run] [--execute]

Fails early unless the expected local project currently owns this machine and
its kubeconfig can reach the expected cluster.

Environment:
  EXPECTED_PROJECT_PATH   Required project path (for example kubernetes/kind)
  EXPECTED_PROJECT_LABEL  Optional label used in help/dry-run output
  KUBECONFIG_PATH         Required kubeconfig path used for the fast reachability probe
  KUBECONFIG_CONTEXT      Optional kubeconfig context used for the fast reachability probe
  PLATFORM_STATUS_SCRIPT  Optional override for scripts/platform-status.sh

$(shell_cli_standard_options)
EOF
}

die() {
  local message="$1"
  printf 'FAIL %s\n' "${message}" >&2
  exit 1
}

blocked() {
  local message="$1"
  printf 'BLOCKED %s\n' "${message}" >&2
  exit 2
}

stop_hint_for_project_path() {
  case "${1:-}" in
    kubernetes/kind)
      printf 'make -C kubernetes/kind stop-kind'
      ;;
    kubernetes/lima)
      printf 'make -C kubernetes/lima stop-lima'
      ;;
    kubernetes/slicer)
      printf 'make -C kubernetes/slicer stop-slicer'
      ;;
    sd-wan/lima)
      printf 'make -C sd-wan/lima down'
      ;;
    *)
      printf ''
      ;;
  esac
}

shell_cli_handle_standard_no_args usage "would verify that ${EXPECTED_PROJECT_LABEL} owns this machine and is reachable" "$@"

[ -n "${EXPECTED_PROJECT_PATH}" ] || die "EXPECTED_PROJECT_PATH must be set"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"
[ -x "${PLATFORM_STATUS_SCRIPT}" ] || die "Platform status helper not found or not executable: ${PLATFORM_STATUS_SCRIPT}"
[ -n "${kubeconfig_path}" ] || die "KUBECONFIG_PATH or KUBECONFIG must be set"

status_json="$("${PLATFORM_STATUS_SCRIPT}" --execute --output json)" || die "Failed to inspect local runtime status with ${PLATFORM_STATUS_SCRIPT}"

expected_project_key="$(jq -r --arg path "${EXPECTED_PROJECT_PATH}" '.projects | to_entries[] | select(.value.path == $path) | .key' <<<"${status_json}" | head -n 1)"
[ -n "${expected_project_key}" ] || die "Unknown EXPECTED_PROJECT_PATH: ${EXPECTED_PROJECT_PATH}"

overall_state="$(jq -r '.overall_state // "unknown"' <<<"${status_json}")"
active_project_path="$(jq -r '.active_project_path // empty' <<<"${status_json}")"
expected_project_state="$(jq -r --arg key "${expected_project_key}" '.projects[$key].state // "unknown"' <<<"${status_json}")"

if [ "${overall_state}" = "conflict" ]; then
  blocked $'Multiple tracked platform surfaces are active on this machine.\nInspect the full local runtime state with:\n  make status'
fi

if [ -n "${active_project_path}" ] && [ "${active_project_path}" != "${EXPECTED_PROJECT_PATH}" ]; then
  stop_hint="$(stop_hint_for_project_path "${active_project_path}")"
  message="This machine is currently being served by ${active_project_path}, not ${EXPECTED_PROJECT_PATH}."
  if [ -n "${stop_hint}" ]; then
    message+=$'\n'"Clear the conflicting surface first:"$'\n'"  ${stop_hint}"
  fi
  message+=$'\n'"Inspect the full local runtime state with:"$'\n'"  make status"
  blocked "${message}"
fi

case "${expected_project_state}" in
  absent|stopped)
    blocked "${EXPECTED_PROJECT_PATH} is not running on this machine.
Inspect the local runtime state with:
  make status"
    ;;
  paused)
    blocked "${EXPECTED_PROJECT_PATH} is paused on this machine.
Inspect the local runtime state with:
  make status"
    ;;
esac

[ -f "${kubeconfig_path}" ] || blocked "Kubeconfig not found: ${kubeconfig_path}"

kubectl_args=(get nodes --request-timeout=5s)
if [ -n "${kubeconfig_context}" ]; then
  kubectl_args=(--context "${kubeconfig_context}" "${kubectl_args[@]}")
fi

if ! KUBECONFIG="${kubeconfig_path}" kubectl "${kubectl_args[@]}" >/dev/null 2>&1; then
  context_note=""
  if [ -n "${kubeconfig_context}" ]; then
    context_note=" (context ${kubeconfig_context})"
  fi
  blocked "${EXPECTED_PROJECT_PATH} is not reachable via kubeconfig ${kubeconfig_path}${context_note}.
Inspect the local runtime state with:
  make status"
fi

context_note=""
if [ -n "${kubeconfig_context}" ]; then
  context_note=" (context ${kubeconfig_context})"
fi
printf 'OK   %s is active on this machine and reachable via kubeconfig %s%s. Proceeding with checks.\n' \
  "${EXPECTED_PROJECT_PATH}" \
  "${kubeconfig_path}" \
  "${context_note}"
