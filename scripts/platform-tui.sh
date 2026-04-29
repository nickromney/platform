#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT:-${REPO_ROOT}/scripts/platform-status.sh}"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Launches the Gum-based local runtime chooser. When Gum is unavailable or the
session is non-interactive, this falls back to plain `platform-status` text.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

print_summary() {
  local json_payload="$1"
  local summary=""

  summary="$(jq -r '
    [
      "Overall: \(.overall_state)",
      "Active cluster variant: \((.active_cluster_variant_path // "none"))",
      "Active variant: \((.active_variant_path // "none"))"
    ] | join("\n")
  ' <<<"${json_payload}")"

  gum style --border rounded --padding "1 2" "${summary}"
}

variant_menu() {
  local json_payload="$1"
  local options=""

  options="$(jq -r '
    . as $root
    | $root.variants_order[]
    | ($root.variants[.].path)
  ' <<<"${json_payload}")"

  {
    printf '%s\n' "${options}"
    printf '%s\n' 'Refresh'
    printf '%s\n' 'Quit'
  } | gum choose --header "Select variant"
}

action_menu() {
  local json_payload="$1"
  local variant_path="$2"
  local options=""

  options="$(jq -r --arg variant_path "${variant_path}" '
    .actions[]
    | select(.variant_path == $variant_path)
    | .label
  ' <<<"${json_payload}")"

  {
    printf '%s\n' "${options}"
    printf '%s\n' 'Back'
    printf '%s\n' 'Quit'
  } | sed '/^[[:space:]]*$/d' | gum choose --header "Select action"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
  exit 1
done

shell_cli_maybe_execute_or_preview_summary usage "would open the local runtime chooser"

if [ "${NO_TUI:-}" = "1" ] || [ ! -t 0 ] || [ ! -t 1 ] || ! have_cmd gum; then
  exec "${PLATFORM_STATUS_SCRIPT}" --execute --output text
fi

while :; do
  status_json="$("${PLATFORM_STATUS_SCRIPT}" --execute --output json)"
  print_summary "${status_json}"

  selected_variant="$(variant_menu "${status_json}")"
  case "${selected_variant}" in
    ''|Quit)
      exit 0
      ;;
    Refresh)
      continue
      ;;
  esac

  while :; do
    selected_action_label="$(action_menu "${status_json}" "${selected_variant}")"
    case "${selected_action_label}" in
      ''|Quit)
        exit 0
        ;;
      Back)
        break
        ;;
    esac

    selected_action_json="$(jq -c --arg variant_path "${selected_variant}" --arg label "${selected_action_label}" '
      .actions[]
      | select(.variant_path == $variant_path and .label == $label)
    ' <<<"${status_json}")"

    [ -n "${selected_action_json}" ] || continue

    action_enabled="$(jq -r '.enabled' <<<"${selected_action_json}")"
    action_reason="$(jq -r '.reason // empty' <<<"${selected_action_json}")"
    action_command="$(jq -r '.command' <<<"${selected_action_json}")"
    action_dangerous="$(jq -r '.dangerous' <<<"${selected_action_json}")"

    if [ "${action_enabled}" != "true" ]; then
      gum style --foreground 214 "${action_reason:-Action unavailable}"
      continue
    fi

    if [ "${action_dangerous}" = "true" ]; then
      gum style --foreground 214 "About to run: ${action_command}"
      if ! gum confirm "Run this action?"; then
        continue
      fi
    else
      gum style --foreground 245 "Running: ${action_command}"
    fi

    exec bash -lc "${action_command}"
  done
done
