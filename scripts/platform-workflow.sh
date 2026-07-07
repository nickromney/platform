#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKFLOW_OPTIONS_RENDERER="${REPO_ROOT}/kubernetes/workflow/render-options.sh"
WORKFLOW_OPTIONS_FILE="${PLATFORM_WORKFLOW_OPTIONS_FILE:-${REPO_ROOT}/.run/workflow/options.json}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

OUTPUT_FORMAT="text"
TARGET="kind"
STAGE="700"
ACTION="plan"
AUTO_APPROVE="0"
TFVARS_FILE=""
SAVE_PROFILE_NAME=""
PROFILES_DIR=""
APP_OVERRIDES=()
PRESET_RESOURCE_PROFILE="default"
PRESET_IMAGE_DISTRIBUTION="default"
PRESET_NETWORK_PROFILE="default"
PRESET_OBSERVABILITY_STACK="default"
PRESET_IDENTITY_STACK="default"
PRESET_APP_SET="default"
CUSTOM_OVERRIDES=()
WORKFLOW_SCRIPT_ARGS=()
LOCAL_REGISTRY_RUNTIME_HOST_CACHE=""
LOCAL_REGISTRY_RUNTIME_HOST_CACHE_SET=0
LOCAL_REGISTRY_PUSH_HOST_CACHE=""
LOCAL_REGISTRY_PUSH_HOST_CACHE_SET=0

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ <options|preview|apply|save-profile> [options] [--dry-run] [--execute]

Builds a stable platform workflow command from operator intent. The workflow
core is non-interactive so the TUI, browser UI, and scripts can share the same
variant/stage/action contract.

Subcommands:
  options   List supported variants, stages, actions, and app toggles
  preview   Render the generated tfvars fragment and make command
  apply     Render the generated tfvars fragment and execute the make command
  save-profile
            Persist generated tfvars as a named variant profile

Workflow options:
  --variant kind|lima             Solution variant (default: kind)
  --stage 100|200|...|900
                                  Cumulative stage or named stage-like target (default: 700)
  --action readiness|plan|apply|reset|state-reset|status|show-urls|check-health|check-security|check-rbac
                                  Make workflow action (default: plan)
  --profile-name NAME             Name for save-profile output
  --profiles-dir PATH             Directory for save-profile output
  --preset group=value            Select one preset per group. Groups:
                                    resource-profile, image-distribution,
                                    network-profile, observability-stack,
                                    identity-stack, app-set
  --set option=value              Custom option override rendered to generated tfvars
  --app NAME=on|off               Override an app repo/workload toggle listed by options
  --tfvars-file PATH              Generated tfvars path (default: .run/operator/<variant>-stage<stage>.tfvars)
  --auto-approve                  Add AUTO_APPROVE=1 for apply/reset-capable workflows
  --output text|json              Output format (default: text)
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

die_usage() {
  printf '%s\n' "$*" >&2
  exit 2
}

require_value() {
  local flag="$1"
  local value="${2-}"

  if [[ -z "${value}" ]]; then
    shell_cli_missing_value "$(shell_cli_script_name)" "${flag}"
    exit 2
  fi
}

target_path() {
  local path=""

  path="$(jq -r --arg id "$1" '.variants[] | select(.id == $id) | .path // empty' "${WORKFLOW_OPTIONS_FILE}")"
  [[ -n "${path}" ]] || return 1
  printf '%s' "${path}"
}

variant_contract_value() {
  local variant="$1"
  local jq_filter="$2"

  jq -r --arg id "${variant}" ".variants[] | select(.id == \$id) | .variant_contract | ${jq_filter} // empty" "${WORKFLOW_OPTIONS_FILE}"
}

repo_path() {
  local path="$1"

  if [[ "${path}" = /* ]]; then
    printf '%s' "${path}"
  else
    printf '%s/%s' "${REPO_ROOT}" "${path}"
  fi
}

target_state_lock_file() {
  local path=""

  path="$(variant_contract_value "$1" '.state.state_lock_file')"
  [[ -n "${path}" ]] || return 1
  repo_path "${path}"
}

workflow_options_json() {
  jq '.' "${WORKFLOW_OPTIONS_FILE}"
}

render_workflow_options() {
  local tmp_file="${WORKFLOW_OPTIONS_FILE}.$$.tmp"

  mkdir -p "$(dirname "${WORKFLOW_OPTIONS_FILE}")"
  "${WORKFLOW_OPTIONS_RENDERER}" --execute >"${tmp_file}"
  mv "${tmp_file}" "${WORKFLOW_OPTIONS_FILE}"
}

validate_target() {
  local expected=""

  if ! target_path "$1" >/dev/null; then
    expected="$(jq -r '[.variants[].id] | join(", ")' "${WORKFLOW_OPTIONS_FILE}")"
    die_usage "Invalid --variant '${1}'. Expected one of: ${expected}"
  fi
}

validate_stage() {
  local expected=""

  if [[ "$1" = "950-local-idp" ]]; then
    die_usage "Stage '950-local-idp' has been removed; use --stage 900 --preset resource-profile=local-idp-16gb"
  fi
  if ! jq -e --arg id "$1" '.stages[] | select(.id == $id)' "${WORKFLOW_OPTIONS_FILE}" >/dev/null; then
    expected="$(jq -r '[.stages[].id] | join(", ")' "${WORKFLOW_OPTIONS_FILE}")"
    die_usage "Invalid --stage '${1}'. Expected one of: ${expected}"
  fi
}

validate_action() {
  local expected=""

  if [[ "$1" = "prereqs" ]]; then
    return 0
  fi
  if ! jq -e --arg id "$1" '.actions[] | select(. == $id)' "${WORKFLOW_OPTIONS_FILE}" >/dev/null; then
    expected="$(jq -r '[.actions[] | select(. != "reset")] | join(", ")' "${WORKFLOW_OPTIONS_FILE}")"
    die_usage "Invalid --action '${1}'. Expected one of: ${expected}"
  fi
}

action_uses_stage() {
  [[ "$(jq -r --arg id "$1" '.action_metadata[]? | select(.id == $id) | .uses_stage // false' "${WORKFLOW_OPTIONS_FILE}")" = "true" ]]
}

action_uses_auto_approve() {
  [[ "$(jq -r --arg id "$1" '.action_metadata[]? | select(.id == $id) | .uses_auto_approve // false' "${WORKFLOW_OPTIONS_FILE}")" = "true" ]]
}

default_profiles_dir() {
  printf '%s/kubernetes/%s/profiles\n' "${REPO_ROOT}" "${TARGET}"
}

save_profile_path() {
  printf '%s/%s.tfvars\n' "${PROFILES_DIR}" "${SAVE_PROFILE_NAME}"
}

validate_profile_name() {
  local name="$1"

  if [[ ! "${name}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die_usage "Invalid --profile-name '${name}'. Use letters, numbers, dot, underscore, or hyphen"
  fi
}

normalize_app_value() {
  case "$1" in
    on|true|1|yes) printf 'true' ;;
    off|false|0|no) printf 'false' ;;
    *) return 1 ;;
  esac
}

set_app_override() {
  local spec="$1"
  local app="${spec%%=*}"
  local raw_value="${spec#*=}"
  local value=""
  local expected=""

  if [[ "${app}" = "${spec}" || -z "${raw_value}" ]]; then
    die_usage "Invalid --app '${spec}'. Expected name=on|off"
  fi

  value="$(normalize_app_value "${raw_value}")" || die_usage "Invalid --app '${spec}'. Expected value on|off"

  if ! jq -e --arg app "${app}" '.apps[] | select(. == $app)' "${WORKFLOW_OPTIONS_FILE}" >/dev/null; then
    expected="$(jq -r '.apps | join(", ")' "${WORKFLOW_OPTIONS_FILE}")"
    die_usage "Invalid --app '${app}'. Expected one of: ${expected}"
  fi

  APP_OVERRIDES+=("${app}=${value}")
}

normalize_group_name() {
  printf '%s' "$1" | tr '-' '_'
}

set_preset() {
  local spec="$1"
  local raw_group="${spec%%=*}"
  local value="${spec#*=}"
  local group=""
  local var_name=""
  local valid_group=""
  local valid_value=""

  if [[ "${raw_group}" = "${spec}" || -z "${value}" ]]; then
    die_usage "Invalid --preset '${spec}'. Expected group=value"
  fi

  group="$(normalize_group_name "${raw_group}")"
  valid_group="$(jq -r --arg group "${group}" '.preset_groups[] | select(.id == $group) | .id // empty' "${WORKFLOW_OPTIONS_FILE}")"
  if [[ -z "${valid_group}" ]]; then
    die_usage "Invalid --preset group '${raw_group}'. Expected one of: $(jq -r '[.preset_groups[].id | gsub("_"; "-")] | join(", ")' "${WORKFLOW_OPTIONS_FILE}")"
  fi

  valid_value="$(jq -r --arg group "${group}" --arg value "${value}" '.preset_groups[] | select(.id == $group) | .presets[] | select(. == $value)' "${WORKFLOW_OPTIONS_FILE}")"
  if [[ -z "${valid_value}" ]]; then
    die_usage "Invalid --preset '${spec}'. Unsupported value for ${raw_group}"
  fi

  case "${group}" in
    resource_profile) var_name="PRESET_RESOURCE_PROFILE" ;;
    image_distribution) var_name="PRESET_IMAGE_DISTRIBUTION" ;;
    network_profile) var_name="PRESET_NETWORK_PROFILE" ;;
    observability_stack) var_name="PRESET_OBSERVABILITY_STACK" ;;
    identity_stack) var_name="PRESET_IDENTITY_STACK" ;;
    app_set) var_name="PRESET_APP_SET" ;;
    *) die_usage "Invalid --preset group '${raw_group}'. Expected one of: resource-profile, image-distribution, network-profile, observability-stack, identity-stack, app-set" ;;
  esac
  printf -v "${var_name}" '%s' "${value}"
}

validate_preset_selection() {
  local error=""

  error="$(
    jq -r \
      --arg variant "${TARGET}" \
      --arg stage "${STAGE}" \
      --arg resource_profile "${PRESET_RESOURCE_PROFILE}" \
      --arg image_distribution "${PRESET_IMAGE_DISTRIBUTION}" \
      --arg network_profile "${PRESET_NETWORK_PROFILE}" \
      --arg observability_stack "${PRESET_OBSERVABILITY_STACK}" \
      --arg identity_stack "${PRESET_IDENTITY_STACK}" \
      --arg app_set "${PRESET_APP_SET}" \
      '
        def selected_presets:
          [
            {group: "resource_profile", preset: $resource_profile},
            {group: "image_distribution", preset: $image_distribution},
            {group: "network_profile", preset: $network_profile},
            {group: "observability_stack", preset: $observability_stack},
            {group: "identity_stack", preset: $identity_stack},
            {group: "app_set", preset: $app_set}
          ]
          | map(select(.preset != "default"));
        def display_group($group):
          $group | gsub("_"; "-");
        def selected_preset_error($options; $selection):
          ([$options.presets[] | select(.group == $selection.group and .id == $selection.preset)][0]) as $preset
          | (display_group($selection.group)) as $display_group
          | if (($preset.variants // []) | index($variant) | not) then
              "Preset \($display_group)=\($selection.preset) is not available for variant \($variant)"
            elif (($preset.introduced_at_stage // "") != "" and (($stage | tonumber) < ($preset.introduced_at_stage | tonumber))) then
              "Preset \($display_group)=\($selection.preset) requires stage \($preset.introduced_at_stage) or later"
            else
              empty
            end;
        . as $options
        | [selected_presets[] | selected_preset_error($options; .)][0] // empty
      ' "${WORKFLOW_OPTIONS_FILE}"
  )"
  [[ -z "${error}" ]] || die_usage "${error}"
}

normalize_custom_bool() {
  case "$1" in
    on|true|1|yes) printf 'true' ;;
    off|false|0|no) printf 'false' ;;
    *) return 1 ;;
  esac
}

normalize_custom_override() {
  local spec="$1"
  local key="${spec%%=*}"
  local raw_value="${spec#*=}"
  local value=""

  if [[ "${key}" = "${spec}" || -z "${key}" ]]; then
    die_usage "Invalid --set '${spec}'. Expected option=value"
  fi

  case "${key}" in
    worker_count)
      [[ "${raw_value}" =~ ^[0-9]+$ ]] || die_usage "Invalid --set '${spec}'. worker_count must be an integer"
      printf '%s=%s' "${key}" "${raw_value}"
      ;;
    node_image|host_local_registry_host|host_local_registry_scheme)
      [[ -n "${raw_value}" ]] || die_usage "Invalid --set '${spec}'. Value must not be empty"
      printf '%s=%s' "${key}" "${raw_value}"
      ;;
    sso_provider)
      case "${raw_value}" in
        keycloak) printf '%s=%s' "${key}" "${raw_value}" ;;
        *) die_usage "Invalid --set '${spec}'. sso_provider must be keycloak" ;;
      esac
      ;;
    enable_backstage|enable_host_local_registry|enable_image_preload|enable_prometheus|enable_grafana|enable_victoria_logs|enable_otel_gateway|enable_headlamp|enable_observability_agent|enable_app_repo_sentiment|enable_app_repo_subnetcalc|enable_actions_runner|enable_apps_dir_mount|enable_docker_socket_mount)
      value="$(normalize_custom_bool "${raw_value}")" || die_usage "Invalid --set '${spec}'. Expected boolean value on|off"
      printf '%s=%s' "${key}" "${value}"
      ;;
    *)
      die_usage "Invalid --set option '${key}'. This workflow currently exposes worker_count, node_image, local registry, app, observability, identity, and Backstage toggles"
      ;;
  esac
}

set_custom_override() {
  CUSTOM_OVERRIDES+=("$(normalize_custom_override "$1")")
}

default_tfvars_file() {
  printf '%s/.run/operator/%s-stage%s.tfvars\n' "${REPO_ROOT}" "${TARGET}" "${STAGE}"
}

has_tfvars_overrides() {
  [[ "${#APP_OVERRIDES[@]}" -gt 0 ||
    "${PRESET_RESOURCE_PROFILE}" != "default" ||
    "${PRESET_IMAGE_DISTRIBUTION}" != "default" ||
    "${PRESET_OBSERVABILITY_STACK}" != "default" ||
    "${PRESET_IDENTITY_STACK}" != "default" ||
    "${PRESET_APP_SET}" != "default" ||
    "${#CUSTOM_OVERRIDES[@]}" -gt 0 ]]
}

app_tfvar_name() {
  local app="$1"

  printf 'enable_app_repo_%s' "${app//-/_}"
}

local_registry_runtime_host() {
  if [[ "${LOCAL_REGISTRY_RUNTIME_HOST_CACHE_SET}" -ne 1 ]]; then
    LOCAL_REGISTRY_RUNTIME_HOST_CACHE="$(variant_contract_value "${TARGET}" '.registry.runtime_host')"
    LOCAL_REGISTRY_RUNTIME_HOST_CACHE_SET=1
  fi
  printf '%s\n' "${LOCAL_REGISTRY_RUNTIME_HOST_CACHE}"
}

local_registry_push_host() {
  if [[ "${LOCAL_REGISTRY_PUSH_HOST_CACHE_SET}" -ne 1 ]]; then
    LOCAL_REGISTRY_PUSH_HOST_CACHE="$(variant_contract_value "${TARGET}" '.registry.push_host')"
    LOCAL_REGISTRY_PUSH_HOST_CACHE_SET=1
  fi
  printf '%s\n' "${LOCAL_REGISTRY_PUSH_HOST_CACHE}"
}

prime_variant_registry_cache() {
  local_registry_runtime_host >/dev/null
  local_registry_push_host >/dev/null
}

hcl_string() {
  jq -Rn --arg value "$1" '$value'
}

render_assignment() {
  local key="$1"
  local value="$2"
  local source="$3"
  local rendered="${value}"

  case "${key}" in
    worker_count) rendered="${value}" ;;
    enable_*|argocd_*|prefer_external_*) rendered="${value}" ;;
    *) rendered="$(hcl_string "${value}")" ;;
  esac

  printf '# Source: %s\n' "${source}"
  printf '%s = %s\n\n' "${key}" "${rendered}"
}

render_preset_tfvars() {
  local registry_host=""
  registry_host="$(local_registry_runtime_host)"

  jq -r \
    --arg registry_host "${registry_host}" \
    --arg resource_profile "${PRESET_RESOURCE_PROFILE}" \
    --arg image_distribution "${PRESET_IMAGE_DISTRIBUTION}" \
    --arg observability_stack "${PRESET_OBSERVABILITY_STACK}" \
    --arg identity_stack "${PRESET_IDENTITY_STACK}" \
    --arg app_set "${PRESET_APP_SET}" \
    '
      def selected_presets:
        [
          {group: "resource_profile", preset: $resource_profile},
          {group: "image_distribution", preset: $image_distribution},
          {group: "observability_stack", preset: $observability_stack},
          {group: "identity_stack", preset: $identity_stack},
          {group: "app_set", preset: $app_set}
        ]
        | map(select(.preset != "default"));
      def subvars:
        if type == "object" then with_entries(.value |= subvars)
        elif type == "array" then map(subvars)
        elif type == "string" then gsub("\\$\\{local_registry_runtime_host\\}"; $registry_host)
        else . end;
      def hcl_key:
        if test("^[A-Za-z_][A-Za-z0-9_]*$") then . else @json end;
      def hcl:
        if type == "boolean" or type == "number" then tostring
        elif type == "object" then
          "{\n" + (to_entries | map("  " + (.key | hcl_key) + " = " + (.value | hcl)) | join("\n")) + "\n}"
        else @json
        end;
      selected_presets[] as $selection
      | .presets[]
      | select(.group == $selection.group and .id == $selection.preset)
      | ("preset " + ($selection.group | gsub("_"; "-")) + "=" + $selection.preset) as $source
      | .overlay
      | subvars
      | to_entries[]
      | "# Source: \($source)\n\(.key) = \(.value | hcl)\n"
    ' "${WORKFLOW_OPTIONS_FILE}"
}

render_custom_overrides() {
  local override=""
  local key=""
  local value=""

  for override in "${CUSTOM_OVERRIDES[@]}"; do
    key="${override%%=*}"
    value="${override#*=}"
    render_assignment "${key}" "${value}" "custom override"
  done
}

active_presets_json() {
  jq -n \
    --arg resource_profile "${PRESET_RESOURCE_PROFILE}" \
    --arg image_distribution "${PRESET_IMAGE_DISTRIBUTION}" \
    --arg network_profile "${PRESET_NETWORK_PROFILE}" \
    --arg observability_stack "${PRESET_OBSERVABILITY_STACK}" \
    --arg identity_stack "${PRESET_IDENTITY_STACK}" \
    --arg app_set "${PRESET_APP_SET}" \
    '{
      resource_profile: $resource_profile,
      image_distribution: $image_distribution,
      network_profile: $network_profile,
      observability_stack: $observability_stack,
      identity_stack: $identity_stack,
      app_set: $app_set
    }'
}

custom_overrides_json() {
  if [[ "${#CUSTOM_OVERRIDES[@]}" -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${CUSTOM_OVERRIDES[@]}" | jq -R 'split("=") | {id: .[0], value: (.[1:] | join("="))}' | jq -s '.'
}

app_overrides_json() {
  local override=""

  if [[ "${#APP_OVERRIDES[@]}" -eq 0 ]]; then
    printf '{}'
    return 0
  fi
  printf '%s\n' "${APP_OVERRIDES[@]}" |
    jq -R 'split("=") | {(.[0]): (.[1] == "true")}' |
    jq -s 'add'
}

warnings_json() {
  local warnings=()
  local override=""

  if [[ "${PRESET_RESOURCE_PROFILE}" = "airplane" || "${PRESET_IMAGE_DISTRIBUTION}" = "airplane" ]]; then
    warnings+=("Airplane mode currently prefers local cache/preload paths; strict fail-closed cache validation is still a future readiness check.")
  fi
  for override in "${CUSTOM_OVERRIDES[@]}"; do
    case "${override%%=*}" in
      worker_count|node_image)
        warnings+=("Changing ${override%%=*} may recreate or restart the cluster because it changes the stage 100 substrate boundary.")
        ;;
    esac
  done

  if [[ "${#warnings[@]}" -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\n' "${warnings[@]}" | jq -R . | jq -s '.'
}

preset_summary_text() {
  printf 'resource=%s, image=%s, network=%s, observability=%s, identity=%s, apps=%s' \
    "${PRESET_RESOURCE_PROFILE}" \
    "${PRESET_IMAGE_DISTRIBUTION}" \
    "${PRESET_NETWORK_PROFILE}" \
    "${PRESET_OBSERVABILITY_STACK}" \
    "${PRESET_IDENTITY_STACK}" \
    "${PRESET_APP_SET}"
}

render_tfvars() {
  local override=""
  local app=""
  local value=""

  printf '# Generated by scripts/platform-workflow.sh; safe to delete.\n'
  printf '# Variant: %s, stage: %s\n' "${TARGET}" "${STAGE}"
  printf '\n'
  render_preset_tfvars
  for override in "${APP_OVERRIDES[@]}"; do
    app="${override%%=*}"
    value="${override#*=}"
    render_assignment "$(app_tfvar_name "${app}")" "${value}" "custom app override"
  done
  render_custom_overrides
}

write_tfvars_if_needed() {
  has_tfvars_overrides || return 0
  mkdir -p "$(dirname "${TFVARS_FILE}")"
  render_tfvars >"${TFVARS_FILE}"
}

append_env_override() {
  if [[ "${#WORKFLOW_COMMAND_ARGS[@]}" -eq 0 ]]; then
    WORKFLOW_COMMAND_ARGS+=(env)
  fi
  WORKFLOW_COMMAND_ARGS+=("$1")
}

append_image_distribution_env() {
  case "${PRESET_IMAGE_DISTRIBUTION}" in
    pull)
      case "${TARGET}" in
        kind)
          append_env_override "KIND_IMAGE_DISTRIBUTION_MODE=load"
          append_env_override "KIND_PRELOAD_IMAGES_MODE=off"
          ;;
        lima)
          append_env_override "PLATFORM_LOCAL_IMAGE_CACHE_MODE=off"
          append_env_override "PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=off"
          append_env_override "PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=off"
          ;;
      esac
      ;;
    local-cache)
      case "${TARGET}" in
        kind)
          append_env_override "KIND_IMAGE_DISTRIBUTION_MODE=registry"
          append_env_override "KIND_LOCAL_IMAGE_CACHE_HOST=$(local_registry_runtime_host)"
          append_env_override "KIND_LOCAL_IMAGE_CACHE_PUSH_HOST=$(local_registry_push_host)"
          ;;
        lima)
          append_env_override "PLATFORM_LOCAL_IMAGE_CACHE_MODE=on"
          append_env_override "LOCAL_IMAGE_CACHE_HOST=$(local_registry_runtime_host)"
          append_env_override "LOCAL_IMAGE_CACHE_PUSH_HOST=$(local_registry_push_host)"
          ;;
      esac
      ;;
    preload)
      append_env_override "KIND_IMAGE_DISTRIBUTION_MODE=load"
      append_env_override "KIND_PRELOAD_IMAGES_MODE=on"
      ;;
    baked)
      append_env_override "KIND_IMAGE_DISTRIBUTION_MODE=baked"
      ;;
    airplane)
      case "${TARGET}" in
        kind)
          append_env_override "KIND_IMAGE_DISTRIBUTION_MODE=registry"
          append_env_override "KIND_PRELOAD_IMAGES_MODE=on"
          append_env_override "KIND_LOCAL_IMAGE_CACHE_HOST=$(local_registry_runtime_host)"
          append_env_override "KIND_LOCAL_IMAGE_CACHE_PUSH_HOST=$(local_registry_push_host)"
          append_env_override "KIND_LOCAL_IMAGE_CACHE_OPTIONAL=0"
          ;;
        lima)
          append_env_override "PLATFORM_LOCAL_IMAGE_CACHE_MODE=on"
          append_env_override "PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=on"
          append_env_override "PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=on"
          append_env_override "LOCAL_IMAGE_CACHE_HOST=$(local_registry_runtime_host)"
          append_env_override "LOCAL_IMAGE_CACHE_PUSH_HOST=$(local_registry_push_host)"
          append_env_override "LOCAL_IMAGE_CACHE_OPTIONAL=0"
          ;;
      esac
      ;;
    default) ;;
  esac
}

append_network_profile_env() {
  case "${PRESET_NETWORK_PROFILE}" in
    cilium) ;;
    default) ;;
  esac
}

build_command_args() {
  local stack_path="$1"
  WORKFLOW_COMMAND_ARGS=()
  append_image_distribution_env
  append_network_profile_env
  if has_tfvars_overrides; then
    append_env_override "PLATFORM_TFVARS=${TFVARS_FILE}"
  fi
  WORKFLOW_COMMAND_ARGS+=(make -C "${stack_path}")
  if action_uses_stage "${ACTION}"; then
    WORKFLOW_COMMAND_ARGS+=("${STAGE}")
  fi
  WORKFLOW_COMMAND_ARGS+=("${ACTION}")
  if [[ "${AUTO_APPROVE}" = "1" ]] && action_uses_auto_approve "${ACTION}"; then
    WORKFLOW_COMMAND_ARGS+=(AUTO_APPROVE=1)
  fi
}

check_state_lock_before_run() {
  local lock_file=""
  local reset_command=""
  local lock_summary=""

  case "${ACTION}" in
    reset|state-reset) return 0 ;;
  esac

  lock_file="$(target_state_lock_file "${TARGET}")"
  [[ -e "${lock_file}" ]] || return 0

  reset_command="$(shell_cli_print_command make -C "${STACK_PATH}" state-reset AUTO_APPROVE=1)"
  printf 'Terraform/OpenTofu state lock present: %s\n' "${lock_file}" >&2
  if command -v jq >/dev/null 2>&1; then
    lock_summary="$(jq -r '[.Operation,.Who,.Created] | map(select(. != null and . != "")) | join("; ")' "${lock_file}" 2>/dev/null || true)"
    if [[ -n "${lock_summary}" ]]; then
      printf 'Lock: %s\n' "${lock_summary}" >&2
    fi
  fi
  printf 'Refusing to run %s while the previous Terraform/OpenTofu operation may still be active.\n' "${ACTION}" >&2
  printf 'To clear a stale lock after confirming no operation is active, run:\n  %s\n' "${reset_command}" >&2
  return 2
}

command_string() {
  shell_cli_print_command "${WORKFLOW_COMMAND_ARGS[@]}"
}

append_workflow_script_preset_arg() {
  local group="$1"
  local value="$2"

  [[ "${value}" != "default" ]] || return 0
  WORKFLOW_SCRIPT_ARGS+=(--preset "${group}=${value}")
}

build_workflow_script_args() {
  local subcommand="$1"
  local standard_flag="$2"
  local override=""

  WORKFLOW_SCRIPT_ARGS=("${subcommand}" "${standard_flag}")
  if [[ "${subcommand}" = "preview" ]]; then
    WORKFLOW_SCRIPT_ARGS+=(--output json)
  fi
  WORKFLOW_SCRIPT_ARGS+=(--variant "${TARGET}" --stage "${STAGE}" --action "${ACTION}")

  append_workflow_script_preset_arg resource-profile "${PRESET_RESOURCE_PROFILE}"
  append_workflow_script_preset_arg image-distribution "${PRESET_IMAGE_DISTRIBUTION}"
  append_workflow_script_preset_arg network-profile "${PRESET_NETWORK_PROFILE}"
  append_workflow_script_preset_arg observability-stack "${PRESET_OBSERVABILITY_STACK}"
  append_workflow_script_preset_arg identity-stack "${PRESET_IDENTITY_STACK}"
  append_workflow_script_preset_arg app-set "${PRESET_APP_SET}"

  for override in "${CUSTOM_OVERRIDES[@]}"; do
    WORKFLOW_SCRIPT_ARGS+=(--set "${override}")
  done
  for override in "${APP_OVERRIDES[@]}"; do
    WORKFLOW_SCRIPT_ARGS+=(--app "${override}")
  done
  if has_tfvars_overrides; then
    WORKFLOW_SCRIPT_ARGS+=(--tfvars-file "${TFVARS_FILE}")
  fi
  if [[ "${AUTO_APPROVE}" = "1" ]] && action_uses_auto_approve "${ACTION}"; then
    WORKFLOW_SCRIPT_ARGS+=(--auto-approve)
  fi
}

workflow_command_string() {
  local subcommand="$1"
  local standard_flag="$2"

  build_workflow_script_args "${subcommand}" "${standard_flag}"
  shell_cli_print_command scripts/platform-workflow.sh "${WORKFLOW_SCRIPT_ARGS[@]}"
}

readiness_command_string() {
  local command=""

  command="$(variant_contract_value "${TARGET}" '.readiness.command')"
  if [[ -n "${command}" ]]; then
    printf '%s' "${command}"
    return 0
  fi
  shell_cli_print_command make -C "${STACK_PATH}" readiness
}

command_preview_json() {
  local make_command=""
  local workflow_execute=""
  local workflow_dry_run=""
  local workflow_preview_json=""
  local readiness_command=""

  make_command="$(command_string)"
  workflow_execute="$(workflow_command_string apply --execute)"
  workflow_dry_run="$(workflow_command_string apply --dry-run)"
  workflow_preview_json="$(workflow_command_string preview --execute)"
  readiness_command="$(readiness_command_string)"

  jq -n \
    --arg make_command "${make_command}" \
    --arg workflow_execute "${workflow_execute}" \
    --arg workflow_dry_run "${workflow_dry_run}" \
    --arg workflow_preview_json "${workflow_preview_json}" \
    --arg readiness_command "${readiness_command}" \
    '{
      make: $make_command,
      workflow_execute: $workflow_execute,
      workflow_dry_run: $workflow_dry_run,
      workflow_preview_json: $workflow_preview_json,
      readiness: $readiness_command
    }'
}

print_options() {
  case "${OUTPUT_FORMAT}" in
    text)
      jq -r '
        "Variants:",
        (.variants[] | "  \(.id)    \(.class)  \(.path)"),
        "",
        "Variant classes:",
        (.variant_classes[] | "  \(.id)  " + (if .supported_now then "supported now" else "future adapter contract" end)),
        "",
        "Stages:",
        (.stages[] | "  \(.id) \(.label)"),
        "",
        "Actions:",
        (.actions[] | "  \(.)"),
        "",
        "App toggles:",
        (.apps[] | "  \(.)=on|off"),
        "",
        "Preset groups:",
        (.preset_groups[] | "  \(.id | gsub("_"; "-"))=\(.presets | join("|"))"),
        "",
        "Custom overrides:",
        "  --set worker_count=2",
        "  --set enable_backstage=off",
        "  --set enable_app_repo_subnetcalc=off",
        ""
      ' "${WORKFLOW_OPTIONS_FILE}"
      ;;
    json)
      workflow_options_json
      ;;
    *) die_usage "Invalid --output '${OUTPUT_FORMAT}'. Expected text or json" ;;
  esac
}

print_preview() {
  local stack_path="$1"
  local command=""
  local options_json=""
  command="$(command_string)"

  case "${OUTPUT_FORMAT}" in
    text)
      printf 'Variant: %s (%s)\n' "${TARGET}" "${stack_path}"
      printf 'Stage: %s\n' "${STAGE}"
      printf 'Action: %s\n' "${ACTION}"
      printf 'Presets: %s\n' "$(preset_summary_text)"
      if [[ "${#CUSTOM_OVERRIDES[@]}" -gt 0 ]]; then
        printf 'Custom overrides: %s\n' "${CUSTOM_OVERRIDES[*]}"
      else
        printf 'Custom overrides: none\n'
      fi
      if has_tfvars_overrides; then
        printf 'Generated tfvars: %s\n' "${TFVARS_FILE}"
        printf '\n'
        render_tfvars
        printf '\n'
      else
        printf 'Generated tfvars: none\n\n'
      fi
      printf 'Command:\n  %s\n' "${command}"
      ;;
    json)
      options_json="$(workflow_options_json)"
      jq -n \
        --arg variant_id "${TARGET}" \
        --arg stack_path "${stack_path}" \
        --arg stage "${STAGE}" \
        --arg action "${ACTION}" \
        --arg tfvars_file "$(has_tfvars_overrides && printf '%s' "${TFVARS_FILE}")" \
        --arg tfvars_excerpt "$(has_tfvars_overrides && render_tfvars)" \
        --arg command "${command}" \
        --argjson options "${options_json}" \
        --argjson presets "$(active_presets_json)" \
        --argjson custom_overrides "$(custom_overrides_json)" \
        --argjson warnings "$(warnings_json)" \
        --argjson has_tfvars "$(has_tfvars_overrides && printf true || printf false)" \
        --argjson app_overrides "$(app_overrides_json)" \
        --argjson command_preview "$(command_preview_json)" \
        '{
          variant: ($options.variants[] | select(.id == $variant_id)),
          stack_path: $stack_path,
          stage: $stage,
          stage_metadata: ($options.stages[] | select(.id == $stage)),
          contexts: [
            ($options.variants[] | select(.id == $variant_id) | .contexts[]) as $context_id |
            $options.contexts[] |
            select(.id == $context_id)
          ],
          contract_requirements: [
            ($options.stages[] | select(.id == $stage) | .contracts[]?) as $contract_id |
            $options.contracts[] |
            select(.id == $contract_id)
          ],
          effective_config: {
            source_precedence: $options.source_precedence,
            presets: $presets,
            custom_overrides: $custom_overrides
          },
          action: $action,
          profile: {name: null, path: null},
          tfvars_file: (if $has_tfvars then $tfvars_file else null end),
          generated_tfvars: (if $has_tfvars then $tfvars_excerpt else null end),
          presets: $presets,
          custom_overrides: $custom_overrides,
          warnings: $warnings,
          app_overrides: $app_overrides,
          command: $command,
          command_preview: $command_preview
        }'
      ;;
    *) die_usage "Invalid --output '${OUTPUT_FORMAT}'. Expected text or json" ;;
  esac
}

save_profile() {
  local output_path=""

  if [[ -z "${SAVE_PROFILE_NAME}" ]]; then
    die_usage "Missing --profile-name for save-profile"
  fi
  validate_profile_name "${SAVE_PROFILE_NAME}"
  if ! has_tfvars_overrides; then
    die_usage "save-profile requires at least one preset, --set override, or --app override"
  fi
  if [[ -z "${PROFILES_DIR}" ]]; then
    PROFILES_DIR="$(default_profiles_dir)"
  fi

  output_path="$(save_profile_path)"
  mkdir -p "${PROFILES_DIR}"
  render_tfvars >"${output_path}"

  case "${OUTPUT_FORMAT}" in
    text)
      printf 'Saved profile: %s\n' "${output_path}"
      ;;
    json)
      jq -n \
        --arg variant_id "${TARGET}" \
        --arg name "${SAVE_PROFILE_NAME}" \
        --arg path "${output_path}" \
        '{saved_profile:{variant:$variant_id,name:$name,path:$path}}'
      ;;
    *) die_usage "Invalid --output '${OUTPUT_FORMAT}'. Expected text or json" ;;
  esac
}

SUBCOMMAND=""
LEADING_STANDARD_FLAGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--execute)
      LEADING_STANDARD_FLAGS+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      SUBCOMMAND="$1"
      shift
      break
      ;;
  esac
done
if [[ "${#LEADING_STANDARD_FLAGS[@]}" -gt 0 ]]; then
  set -- "${LEADING_STANDARD_FLAGS[@]}" "$@"
fi

case "${SUBCOMMAND}" in
  options|preview|apply|save-profile) ;;
  '')
    SUBCOMMAND="preview"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    die_usage "Unknown subcommand '${SUBCOMMAND}'. Expected options, preview, apply, or save-profile"
    ;;
esac

render_workflow_options

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --variant)
      require_value "$1" "${2-}"
      TARGET="$2"
      shift 2
      ;;
    --target)
      die_usage "--target has been removed; use --variant"
      ;;
    --stage)
      require_value "$1" "${2-}"
      STAGE="$2"
      shift 2
      ;;
    --action)
      require_value "$1" "${2-}"
      ACTION="$2"
      shift 2
      ;;
    --profile)
      die_usage "--profile has been removed; use --preset resource-profile=local-idp-16gb when you need the local IDP resource profile"
      ;;
    --profile-name)
      require_value "$1" "${2-}"
      SAVE_PROFILE_NAME="$2"
      shift 2
      ;;
    --profiles-dir)
      require_value "$1" "${2-}"
      PROFILES_DIR="$2"
      shift 2
      ;;
    --preset)
      require_value "$1" "${2-}"
      set_preset "$2"
      shift 2
      ;;
    --set)
      require_value "$1" "${2-}"
      set_custom_override "$2"
      shift 2
      ;;
    --app)
      require_value "$1" "${2-}"
      set_app_override "$2"
      shift 2
      ;;
    --tfvars-file)
      require_value "$1" "${2-}"
      TFVARS_FILE="$2"
      shift 2
      ;;
    --auto-approve)
      AUTO_APPROVE="1"
      shift
      ;;
    --output)
      require_value "$1" "${2-}"
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
  esac
done

if [[ "${SUBCOMMAND}" = "options" ]]; then
  if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
    shell_cli_print_dry_run_summary "would list platform workflow options"
    exit 0
  fi

  if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
    usage
    shell_cli_print_dry_run_summary "would list platform workflow options"
    exit 0
  fi

  print_options
  exit 0
fi

validate_target "${TARGET}"
validate_stage "${STAGE}"
validate_action "${ACTION}"
validate_preset_selection

if [[ -z "${TFVARS_FILE}" ]]; then
  TFVARS_FILE="$(default_tfvars_file)"
fi

STACK_PATH="$(target_path "${TARGET}")"
prime_variant_registry_cache
build_command_args "${STACK_PATH}"

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would build ${TARGET} stage ${STAGE} ${ACTION} workflow"
  print_preview "${STACK_PATH}"
  exit 0
fi

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would build ${TARGET} stage ${STAGE} ${ACTION} workflow"
  exit 0
fi

case "${SUBCOMMAND}" in
  options)
    print_options
    ;;
  preview)
    write_tfvars_if_needed
    print_preview "${STACK_PATH}"
    ;;
  apply)
    write_tfvars_if_needed
    print_preview "${STACK_PATH}" >&2
    check_state_lock_before_run
    exec "${WORKFLOW_COMMAND_ARGS[@]}"
    ;;
  save-profile)
    save_profile
    ;;
esac
