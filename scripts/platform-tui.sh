#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT:-${REPO_ROOT}/scripts/platform-status.sh}"
PLATFORM_WORKFLOW_SCRIPT="${PLATFORM_WORKFLOW_SCRIPT:-${REPO_ROOT}/scripts/platform-workflow.sh}"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Launches the platform workflow guide and local runtime chooser. Interactive
sessions use Gum when available and fall back to numbered prompts otherwise.
Non-interactive sessions fall back to plain `platform-status` text.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

tui_is_interactive() {
  [ "${PLATFORM_TUI_NONINTERACTIVE:-}" != "1" ] && [ -t 0 ] && [ -t 1 ]
}

tui_has_gum() {
  [ "${PLATFORM_TUI_FORCE_PLAIN:-}" != "1" ] && have_cmd gum
}

tui_terminal_available() {
  [ -e /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ] && : >/dev/tty 2>/dev/null
}

tui_read_line() {
  local value=""

  if tui_terminal_available; then
    IFS= read -r value </dev/tty || return 1
  else
    IFS= read -r value || return 1
  fi

  printf '%s\n' "${value}"
}

tui_print_terminal() {
  if tui_terminal_available; then
    printf "$@" >/dev/tty
  else
    printf "$@" >&2
  fi
}

tui_plain_choose() {
  local header="$1"
  shift
  local -a items=("$@")
  local choice=""
  local index=""
  local count="${#items[@]}"

  if [ "${count}" -eq 0 ]; then
    return 1
  fi
  if [ "${count}" -eq 1 ]; then
    printf '%s\n' "${items[0]}"
    return 0
  fi

  while :; do
    tui_print_terminal '\n%s\n' "${header}"
    for index in "${!items[@]}"; do
      tui_print_terminal '  %d) %s\n' "$((index + 1))" "${items[$index]}"
    done
    tui_print_terminal 'Select [1-%d]: ' "${count}"

    choice="$(tui_read_line)" || return 1
    case "${choice}" in
      ''|*[!0-9]*)
        tui_print_terminal 'Enter a number from 1 to %d.\n' "${count}"
        ;;
      *)
        if [ "${choice}" -ge 1 ] && [ "${choice}" -le "${count}" ]; then
          printf '%s\n' "${items[$((choice - 1))]}"
          return 0
        fi
        tui_print_terminal 'Enter a number from 1 to %d.\n' "${count}"
        ;;
    esac
  done
}

tui_choose() {
  local header="$1"
  shift

  if tui_has_gum; then
    gum choose \
      --header="${header}" \
      --height="${PLATFORM_TUI_MENU_HEIGHT:-16}" \
      --cursor="➜ " \
      --limit=1 \
      --select-if-one \
      --no-show-help \
      --cursor.foreground=212 \
      --header.foreground=99 \
      --selected.foreground=212 \
      "$@"
    return $?
  fi

  tui_plain_choose "${header}" "$@"
}

tui_choose_from_stdin() {
  local header="$1"
  local -a items=()
  local item=""

  while IFS= read -r item; do
    [ -n "${item}" ] || continue
    items+=("${item}")
  done

  tui_choose "${header}" "${items[@]}"
}

tui_header() {
  if tui_has_gum; then
    gum style \
      --border rounded \
      --padding "0 2" \
      --margin "0 0 1 0" \
      --border-foreground 99 \
      --foreground 255 \
      "$@"
    return $?
  fi

  printf '\n'
  printf '%s\n' "$@"
  printf '\n'
}

tui_panel() {
  if tui_has_gum; then
    gum style \
      --border rounded \
      --padding "1 2" \
      --border-foreground 240 \
      "$@"
    return $?
  fi

  printf '%s\n\n' "$@"
}

tui_note() {
  if tui_has_gum; then
    gum style --foreground 245 "$@"
    return $?
  fi

  printf '%s\n' "$@"
}

tui_warn() {
  if tui_has_gum; then
    gum style --foreground 214 "$@"
    return $?
  fi

  printf '%s\n' "$@"
}

tui_confirm() {
  local prompt="$1"
  local answer=""

  if tui_has_gum; then
    gum confirm "${prompt}"
    return $?
  fi

  tui_print_terminal '%s [y/N]: ' "${prompt}"
  answer="$(tui_read_line)" || return 1
  case "${answer}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
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

  tui_panel "${summary}"
}

variant_menu() {
  tui_choose \
    "Platform TUI / target" \
    "Guided platform workflow" \
    "kubernetes/kind" \
    "kubernetes/lima" \
    "kubernetes/slicer" \
    "Refresh status" \
    "Quit"
}

action_menu() {
  local variant_path="$1"
  local raw_options=""

  case "${variant_path}" in
    kubernetes/kind)
      raw_options="$(cat <<'EOF'
100 apply	kind-apply-100
900 apply	kind-apply-900
950 local IDP apply	kind-apply-950-local-idp
Gitea repo lifecycle demo	kind-gitea-repo-lifecycle-demo
Health	kind-check-health
IDP catalog	kind-idp-catalog
IDP deployments	kind-idp-deployments
IDP environment request	kind-idp-env-create
IDP secrets	kind-idp-secrets
Prereqs	kind-prereqs
Reset	kind-reset
Status	kind-status
Stop	kind-stop
Switch	kind-switch
URLs	kind-show-urls
EOF
)"
      ;;
    kubernetes/lima)
      raw_options="$(cat <<'EOF'
100 apply	lima-apply-100
900 apply	lima-apply-900
Health	lima-check-health
Prereqs	lima-prereqs
Reset	lima-reset
Status	lima-status
Stop	lima-stop
Switch	lima-switch
URLs	lima-show-urls
EOF
)"
      ;;
    kubernetes/slicer)
      raw_options="$(cat <<'EOF'
100 apply	slicer-apply-100
900 apply	slicer-apply-900
Health	slicer-check-health
Prereqs	slicer-prereqs
Reset	slicer-reset
Status	slicer-status
Stop	slicer-stop
Switch	slicer-switch
URLs	slicer-show-urls
EOF
)"
      ;;
    *)
      raw_options=""
      ;;
  esac

  ACTION_MENU_OPTIONS="$(
    {
      printf '%s\t%s\n' 'Back' 'Back'
      printf '%s\n' "${raw_options}"
      printf '%s\t%s\n' 'Quit' 'Quit'
    } | sed '/^[[:space:]]*$/d'
  )"

  printf '%s\n' "${ACTION_MENU_OPTIONS}" | awk -F '\t' '{ print $1 }' | tui_choose_from_stdin "Platform TUI / ${variant_path} / action"
}

action_menu_selected_id() {
  local variant_path="${2:-}"
  local selected_label="$1"

  case "${variant_path}:${selected_label}" in
    kubernetes/kind:Status) printf 'kind-status\n' ;;
    kubernetes/kind:Prereqs) printf 'kind-prereqs\n' ;;
    kubernetes/kind:Health) printf 'kind-check-health\n' ;;
    kubernetes/kind:URLs) printf 'kind-show-urls\n' ;;
    kubernetes/kind:"100 apply") printf 'kind-apply-100\n' ;;
    kubernetes/kind:"900 apply") printf 'kind-apply-900\n' ;;
    kubernetes/kind:"950 local IDP apply") printf 'kind-apply-950-local-idp\n' ;;
    kubernetes/kind:Switch) printf 'kind-switch\n' ;;
    kubernetes/kind:Stop) printf 'kind-stop\n' ;;
    kubernetes/kind:Reset) printf 'kind-reset\n' ;;
    kubernetes/kind:"IDP catalog") printf 'kind-idp-catalog\n' ;;
    kubernetes/kind:"IDP deployments") printf 'kind-idp-deployments\n' ;;
    kubernetes/kind:"IDP environment request") printf 'kind-idp-env-create\n' ;;
    kubernetes/kind:"IDP secrets") printf 'kind-idp-secrets\n' ;;
    kubernetes/kind:"Gitea repo lifecycle demo") printf 'kind-gitea-repo-lifecycle-demo\n' ;;
    kubernetes/lima:Status) printf 'lima-status\n' ;;
    kubernetes/lima:Prereqs) printf 'lima-prereqs\n' ;;
    kubernetes/lima:Health) printf 'lima-check-health\n' ;;
    kubernetes/lima:URLs) printf 'lima-show-urls\n' ;;
    kubernetes/lima:"100 apply") printf 'lima-apply-100\n' ;;
    kubernetes/lima:"900 apply") printf 'lima-apply-900\n' ;;
    kubernetes/lima:Switch) printf 'lima-switch\n' ;;
    kubernetes/lima:Stop) printf 'lima-stop\n' ;;
    kubernetes/lima:Reset) printf 'lima-reset\n' ;;
    kubernetes/slicer:Status) printf 'slicer-status\n' ;;
    kubernetes/slicer:Prereqs) printf 'slicer-prereqs\n' ;;
    kubernetes/slicer:Health) printf 'slicer-check-health\n' ;;
    kubernetes/slicer:URLs) printf 'slicer-show-urls\n' ;;
    kubernetes/slicer:"100 apply") printf 'slicer-apply-100\n' ;;
    kubernetes/slicer:"900 apply") printf 'slicer-apply-900\n' ;;
    kubernetes/slicer:Switch) printf 'slicer-switch\n' ;;
    kubernetes/slicer:Stop) printf 'slicer-stop\n' ;;
    kubernetes/slicer:Reset) printf 'slicer-reset\n' ;;
    *) return 1 ;;
  esac
}

workflow_stage_label() {
  case "$1" in
    "100 cluster") printf '100' ;;
    "200 cilium") printf '200' ;;
    "300 hubble") printf '300' ;;
    "400 argocd") printf '400' ;;
    "500 gitea") printf '500' ;;
    "600 policies") printf '600' ;;
    "700 app repos") printf '700' ;;
    "800 observability") printf '800' ;;
    "900 sso") printf '900' ;;
    "950 local-idp") printf '950-local-idp' ;;
    *) return 1 ;;
  esac
}

workflow_app_arg() {
  local app="$1"
  local selection="$2"

  case "${selection}" in
    "Enable ${app} (stage default)"|"Disable ${app} (stage default)") return 0 ;;
    "Enable ${app}") printf '%s=on\n' "${app}" ;;
    "Disable ${app}") printf '%s=off\n' "${app}" ;;
    *) return 1 ;;
  esac
}

workflow_stage_default_for_app() {
  local target="$1"
  local stage="$2"
  local app="$3"

  case "${stage}:${app}" in
    950-local-idp:sentiment) printf 'enabled' ;;
    950-local-idp:subnetcalc) printf 'disabled' ;;
    100:*|200:*|300:*|400:*|500:*|600:*) printf 'disabled' ;;
    700:*|800:*|900:*) printf 'enabled' ;;
    *) printf 'unknown' ;;
  esac
}

workflow_app_default_choice() {
  local target="$1"
  local stage="$2"
  local app="$3"
  local default_value=""

  default_value="$(workflow_stage_default_for_app "${target}" "${stage}" "${app}")"
  case "${default_value}" in
    enabled) printf 'Enable %s (stage default)\n' "${app}" ;;
    disabled) printf 'Disable %s (stage default)\n' "${app}" ;;
    *) printf '%s stage default unknown\n' "${app}" ;;
  esac
}

workflow_app_override_choice() {
  local target="$1"
  local stage="$2"
  local app="$3"
  local default_value=""

  default_value="$(workflow_stage_default_for_app "${target}" "${stage}" "${app}")"
  case "${default_value}" in
    enabled) printf 'Disable %s\n' "${app}" ;;
    disabled) printf 'Enable %s\n' "${app}" ;;
    *) return 1 ;;
  esac
}

workflow_stage_choice() {
  local target="$1"
  local breadcrumb="$2"

  case "${target}" in
    kind)
      tui_choose \
        "${breadcrumb} / stage" \
        "100 cluster" \
        "200 cilium" \
        "300 hubble" \
        "400 argocd" \
        "500 gitea" \
        "600 policies" \
        "700 app repos" \
        "800 observability" \
        "900 sso" \
        "950 local-idp" \
        Back \
        Quit
      ;;
    lima|slicer)
      tui_choose \
        "${breadcrumb} / stage" \
        "100 cluster" \
        "200 cilium" \
        "300 hubble" \
        "400 argocd" \
        "500 gitea" \
        "600 policies" \
        "700 app repos" \
        "800 observability" \
        "900 sso" \
        Back \
        Quit
      ;;
    *)
      return 1
      ;;
  esac
}

guided_workflow() {
  local target="${1:-}"
  local stage_choice=""
  local stage=""
  local action=""
  local sentiment_choice=""
  local subnetcalc_choice=""
  local sentiment_arg=""
  local subnetcalc_arg=""
  local preview_json=""
  local preview_command=""
  local workflow_args=()

  tui_header "Guided platform workflow" "Choose a stack, stage, action, and app toggles."

  if [ -z "${target}" ]; then
    target="$(tui_choose "Guided workflow / target" kind lima slicer Back Quit)"
    case "${target}" in
      ''|Quit) exit 0 ;;
      Back) return 0 ;;
    esac
  fi

  stage_choice="$(workflow_stage_choice "${target}" "Guided workflow / ${target}")"
  case "${stage_choice}" in
    ''|Quit) exit 0 ;;
    Back) return 0 ;;
  esac
  stage="$(workflow_stage_label "${stage_choice}")"

  action="$(tui_choose "Guided workflow / ${target} / ${stage} / action" plan apply status show-urls check-health check-security check-rbac Back Quit)"
  case "${action}" in
    ''|Quit) exit 0 ;;
    Back) return 0 ;;
  esac

  sentiment_choice="$(tui_choose \
    "Guided workflow / ${target} / ${stage} / ${action} / sentiment" \
    "$(workflow_app_default_choice "${target}" "${stage}" sentiment)" \
    "$(workflow_app_override_choice "${target}" "${stage}" sentiment)" \
    Back \
    Quit)"
  case "${sentiment_choice}" in
    ''|Quit) exit 0 ;;
    Back) return 0 ;;
  esac
  sentiment_arg="$(workflow_app_arg sentiment "${sentiment_choice}")"

  subnetcalc_choice="$(tui_choose \
    "Guided workflow / ${target} / ${stage} / ${action} / subnetcalc" \
    "$(workflow_app_default_choice "${target}" "${stage}" subnetcalc)" \
    "$(workflow_app_override_choice "${target}" "${stage}" subnetcalc)" \
    Back \
    Quit)"
  case "${subnetcalc_choice}" in
    ''|Quit) exit 0 ;;
    Back) return 0 ;;
  esac
  subnetcalc_arg="$(workflow_app_arg subnetcalc "${subnetcalc_choice}")"

  workflow_args=(preview --execute --output json --target "${target}" --stage "${stage}" --action "${action}")
  if [ -n "${sentiment_arg}" ]; then
    workflow_args+=(--app "${sentiment_arg}")
  fi
  if [ -n "${subnetcalc_arg}" ]; then
    workflow_args+=(--app "${subnetcalc_arg}")
  fi
  if [ "${action}" = "apply" ]; then
    workflow_args+=(--auto-approve)
  fi

  preview_json="$("${PLATFORM_WORKFLOW_SCRIPT}" "${workflow_args[@]}")"
  preview_command="$(jq -r '.command' <<<"${preview_json}")"

  tui_panel "$(
    jq -r '
      [
        "Target: \(.target)",
        "Stage: \(.stage)",
        "Action: \(.action)",
        "Sentiment: \(if .app_overrides.sentiment == null then "stage default" else .app_overrides.sentiment end)",
        "Subnetcalc: \(if .app_overrides.subnetcalc == null then "stage default" else .app_overrides.subnetcalc end)",
        "Command: \(.command)"
      ] | join("\n")
    ' <<<"${preview_json}"
  )"

  if ! tui_confirm "Run this workflow?"; then
    return 0
  fi

  workflow_args=(apply --execute --target "${target}" --stage "${stage}" --action "${action}")
  if [ -n "${sentiment_arg}" ]; then
    workflow_args+=(--app "${sentiment_arg}")
  fi
  if [ -n "${subnetcalc_arg}" ]; then
    workflow_args+=(--app "${subnetcalc_arg}")
  fi
  if [ "${action}" = "apply" ]; then
    workflow_args+=(--auto-approve)
  fi

  tui_note "Running: ${preview_command}"
  exec "${PLATFORM_WORKFLOW_SCRIPT}" "${workflow_args[@]}"
}

platform_tui_main() {
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

  if [ "${NO_TUI:-}" = "1" ] || ! tui_is_interactive; then
    exec "${PLATFORM_STATUS_SCRIPT}" --execute --output text
  fi

  while :; do
    tui_header "Platform TUI" "Choose a workflow. Status is loaded when needed."
    selected_variant="$(variant_menu)"
    case "${selected_variant}" in
      ''|Quit)
        exit 0
        ;;
      "Refresh status")
        tui_note "Checking platform status..."
        status_json="$("${PLATFORM_STATUS_SCRIPT}" --execute --output json)"
        print_summary "${status_json}"
        continue
        ;;
      "Guided platform workflow")
        guided_workflow
        continue
        ;;
  esac

    guided_workflow "${selected_variant##*/}"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  platform_tui_main "$@"
fi
