#!/usr/bin/env bash

# An ordered newline-delimited list, supplied by the apply workflow after it
# resolves stage, target and operator overrides. Unset preserves standalone builds.
# Bash 3.2 has no associative arrays, so the memo is a newline-delimited
# key=value string. It holds one entry per toggle, not per image.
IMAGE_SELECTION_CACHE=""
IMAGE_SELECTION_CACHE_KEY=""

# One resolve-tfvar-value.sh subprocess per variable, not per image: the
# platform and workload builders ask about the same handful of toggles.
image_selection_value() {
  local key="$1" file="" default_value="" value=""

  if [ "${IMAGE_SELECTION_CACHE_KEY}" != "${IMAGE_BUILD_TFVARS_FILES:-}" ]; then
    IMAGE_SELECTION_CACHE=""
    IMAGE_SELECTION_CACHE_KEY="${IMAGE_BUILD_TFVARS_FILES:-}"
  fi
  value="$(printf '%s\n' "${IMAGE_SELECTION_CACHE}" | sed -n "s/^${key}=//p" | head -1)"
  if [ -n "${value}" ]; then
    printf '%s\n' "${value}"
    return 0
  fi

  local files=()
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    [ -f "${file}" ] || { echo "Missing image selection tfvars: ${file}" >&2; return 1; }
    files+=("${file}")
  done <<<"${IMAGE_BUILD_TFVARS_FILES}"
  default_value="$(tf_default_from_variables "${key}")"
  value="$("${REPO_ROOT}/kubernetes/scripts/resolve-tfvar-value.sh" --execute "${key}" "${default_value}" "${files[@]}")" || return 1
  IMAGE_SELECTION_CACHE="${IMAGE_SELECTION_CACHE}
${key}=${value}"
  printf '%s\n' "${value}"
}

image_selection_true() {
  [ "$(image_selection_value "$1")" = true ]
}

image_selection_enabled() {
  local category="$1" image_id="$2"
  if [ -z "${IMAGE_BUILD_TFVARS_FILES:-}" ]; then
    [ "${image_id}" != backstage ] || [ "${ENABLE_BACKSTAGE:-false}" = true ]
    return
  fi
  if ! declare -F tf_default_from_variables >/dev/null 2>&1; then
    export VARIABLES_FILE="${VARIABLES_FILE:-${REPO_ROOT}/terraform/kubernetes/variables.tf}"
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh"
  fi
  # Keep these dependencies aligned with terraform/kubernetes/locals.tf.
  if [ "${image_id}" = keycloak ]; then
    image_selection_true enable_sso
    return
  fi
  image_selection_true enable_argocd || return 1
  case "${category}:${image_id}" in
    platform:grafana-victorialogs) image_selection_true enable_grafana ;;
    platform:argo-rollouts-gatewayapi-plugin) image_selection_true enable_progressive_delivery ;;
    platform:idp-core) image_selection_true enable_sso ;;
    platform:backstage) image_selection_true enable_sso && image_selection_true enable_backstage ;;
    platform:platform-mcp|platform:auth-chat|platform:chatgpt-sim)
      image_selection_true enable_sso && {
        image_selection_true enable_apim_simulator ||
        { image_selection_true enable_app_repo_subnetcalc && image_selection_true enable_subnetcalc_apim_gateway; } ||
        image_selection_true enable_agentgateway_ai_gateway
      } ;;
    workload:subnetcalc-apim-simulator)
      image_selection_true enable_apim_simulator ||
        { image_selection_true enable_app_repo_subnetcalc && image_selection_true enable_subnetcalc_apim_gateway; } ;;
    workload:sentiment-*) image_selection_true enable_app_repo_sentiment ;;
    workload:subnetcalc-*) image_selection_true enable_app_repo_subnetcalc ;;
    *) echo "Unknown image selection: ${category}:${image_id}" >&2; return 1 ;;
  esac
}
