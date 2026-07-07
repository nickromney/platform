#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  platform-status-action-catalog.sh --records --variant NAME --variant-path PATH --runtime-present 0|1 --apply-100-enabled 0|1 --apply-100-reason TEXT --apply-900-enabled 0|1 --apply-900-reason TEXT
USAGE
}

bool_json() {
  case "$1" in
    1|true) printf 'true\n' ;;
    0|false) printf 'false\n' ;;
    *)
      printf 'Invalid boolean value: %s\n' "$1" >&2
      return 1
      ;;
  esac
}

build_action_json() {
  local id="$1"
  local label="$2"
  local variant="$3"
  local variant_path="$4"
  local enabled="$5"
  local reason="$6"
  local command="$7"
  local dangerous="$8"

  jq -cn \
    --arg id "${id}" \
    --arg label "${label}" \
    --arg variant "${variant}" \
    --arg variant_path "${variant_path}" \
    --arg reason "${reason}" \
    --arg command "${command}" \
    --argjson enabled "$(bool_json "${enabled}")" \
    --argjson dangerous "$(bool_json "${dangerous}")" \
    '{
      id: $id,
      label: $label,
      variant: $variant,
      variant_path: $variant_path,
      enabled: $enabled,
      reason: (if $reason == "" then null else $reason end),
      command: $command,
      dangerous: $dangerous
    }'
}

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "${value}" ]; then
    printf 'Missing %s\n' "${name}" >&2
    exit 1
  fi
}

mode=""
variant=""
variant_path=""
runtime_present=""
apply_100_enabled=""
apply_100_reason=""
apply_900_enabled=""
apply_900_reason=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --records)
      mode="records"
      shift
      ;;
    --variant)
      variant="${2:-}"
      shift 2
      ;;
    --variant-path)
      variant_path="${2:-}"
      shift 2
      ;;
    --runtime-present)
      runtime_present="${2:-}"
      shift 2
      ;;
    --apply-100-enabled)
      apply_100_enabled="${2:-}"
      shift 2
      ;;
    --apply-100-reason)
      apply_100_reason="${2:-}"
      shift 2
      ;;
    --apply-900-enabled)
      apply_900_enabled="${2:-}"
      shift 2
      ;;
    --apply-900-reason)
      apply_900_reason="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[ "${mode}" = "records" ] || {
  usage >&2
  exit 1
}

require_value "--variant" "${variant}"
require_value "--variant-path" "${variant_path}"
require_value "--runtime-present" "${runtime_present}"
require_value "--apply-100-enabled" "${apply_100_enabled}"
require_value "--apply-900-enabled" "${apply_900_enabled}"

runtime_enabled="${runtime_present}"
running_reason=""
present_reason=""
if [ "${runtime_present}" != "1" ]; then
  running_reason="${variant_path} is not running"
  present_reason="${variant_path} is not present"
fi

case "${variant}" in
  kind)
    status_label="Kind status"
    prereqs_label="Kind prereqs"
    health_label="Kind health"
    urls_label="Kind URLs"
    stop_label="Stop kind"
    reset_label="Reset kind"
    apply_100_label="Kind stage 100 apply"
    apply_900_label="Kind stage 900 apply"
    switch_label="Switch to kind"
    stop_target="stop-kind"
    ;;
  lima)
    status_label="Kubernetes Lima status"
    prereqs_label="Kubernetes Lima prereqs"
    health_label="Kubernetes Lima health"
    urls_label="Kubernetes Lima URLs"
    stop_label="Stop Kubernetes Lima"
    reset_label="Reset Kubernetes Lima"
    apply_100_label="Kubernetes Lima stage 100 apply"
    apply_900_label="Kubernetes Lima stage 900 apply"
    switch_label="Switch to Kubernetes Lima"
    stop_target="stop-lima"
    ;;
  *)
    printf 'Unknown variant: %s\n' "${variant}" >&2
    exit 1
    ;;
esac

build_action_json "${variant}-status" "${status_label}" "${variant}" "${variant_path}" 1 "" "make -C ${variant_path} status" 0
build_action_json "${variant}-prereqs" "${prereqs_label}" "${variant}" "${variant_path}" 1 "" "make -C ${variant_path} prereqs" 0
build_action_json "${variant}-check-health" "${health_label}" "${variant}" "${variant_path}" "${runtime_enabled}" "${running_reason}" "make -C ${variant_path} check-health" 0
build_action_json "${variant}-show-urls" "${urls_label}" "${variant}" "${variant_path}" "${runtime_enabled}" "${running_reason}" "make -C ${variant_path} show-urls" 0
build_action_json "${variant}-stop" "${stop_label}" "${variant}" "${variant_path}" "${runtime_enabled}" "${present_reason}" "make -C ${variant_path} ${stop_target}" 0
build_action_json "${variant}-reset" "${reset_label}" "${variant}" "${variant_path}" "${runtime_enabled}" "${present_reason}" "make -C ${variant_path} reset AUTO_APPROVE=1" 1
build_action_json "${variant}-apply-100" "${apply_100_label}" "${variant}" "${variant_path}" "${apply_100_enabled}" "${apply_100_reason}" "make -C ${variant_path} 100 apply AUTO_APPROVE=1" 1
build_action_json "${variant}-apply-900" "${apply_900_label}" "${variant}" "${variant_path}" "${apply_900_enabled}" "${apply_900_reason}" "make -C ${variant_path} 900 apply AUTO_APPROVE=1" 1
build_action_json "${variant}-switch" "${switch_label}" "${variant}" "${variant_path}" "${apply_900_enabled}" "${apply_900_reason}" "make -C ${variant_path} reset AUTO_APPROVE=1 && make -C ${variant_path} 100 apply AUTO_APPROVE=1 && make -C ${variant_path} 900 apply AUTO_APPROVE=1" 1

if [ "${variant}" = "kind" ]; then
  build_action_json kind-idp-catalog 'IDP catalog' kind kubernetes/kind 1 '' 'make -C kubernetes/kind idp-catalog' 0
  build_action_json kind-idp-env-create 'IDP environment request' kind kubernetes/kind 1 '' 'make -C kubernetes/kind idp-env ACTION=create APP=chatgpt-sim ENV=preview-nr' 0
  build_action_json kind-idp-deployments 'IDP deployments' kind kubernetes/kind 1 '' 'make -C kubernetes/kind idp-deployments' 0
  build_action_json kind-idp-secrets 'IDP secrets' kind kubernetes/kind 1 '' 'make -C kubernetes/kind idp-secrets' 0
  build_action_json kind-idp-scorecards 'IDP scorecards' kind kubernetes/kind 1 '' 'make -C kubernetes/kind idp-scorecards' 0
  build_action_json kind-gitea-repo-lifecycle-demo 'Gitea repo lifecycle demo' kind kubernetes/kind 1 '' 'make -C kubernetes/kind gitea-repo-lifecycle-demo REPO_NAME=chatgpt-sim' 0
fi
