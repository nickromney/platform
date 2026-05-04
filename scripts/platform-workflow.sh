#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
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
APP_SENTIMENT=""
APP_SUBNETCALC=""
PRESET_RESOURCE_PROFILE="default"
PRESET_IMAGE_DISTRIBUTION="default"
PRESET_NETWORK_PROFILE="default"
PRESET_OBSERVABILITY_STACK="default"
PRESET_IDENTITY_STACK="default"
PRESET_APP_SET="default"
CUSTOM_OVERRIDES=()

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
  --variant kind|lima|slicer      Solution variant (default: kind)
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
  --app sentiment=on|off          Override sentiment app repo/workload toggle
  --app subnetcalc=on|off         Override subnetcalc app repo/workload toggle
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
  case "$1" in
    kind) printf 'kubernetes/kind' ;;
    lima) printf 'kubernetes/lima' ;;
    slicer) printf 'kubernetes/slicer' ;;
    *) return 1 ;;
  esac
}

target_state_lock_file() {
  case "$1" in
    kind) printf '%s/terraform/.run/kubernetes/.terraform.tfstate.lock.info\n' "${REPO_ROOT}" ;;
    lima) printf '%s/terraform/.run/kubernetes-lima/.terraform.tfstate.lock.info\n' "${REPO_ROOT}" ;;
    slicer) printf '%s/terraform/.run/kubernetes-slicer/.terraform.tfstate.lock.info\n' "${REPO_ROOT}" ;;
    *) return 1 ;;
  esac
}

workflow_options_json() {
  jq -n '{
    schema_version: "0.2",
    variants: [
      {
        id: "kind",
        path: "kubernetes/kind",
        label: "kind",
        family: "local",
        class: "local-created-cluster",
        lifecycle_mode: "create",
        state_scope: "single-local",
        contexts: ["local-substrate", "platform-stack"],
        contract_outputs: ["cluster-access", "ingress", "registry", "cni", "identity", "resource-sizing", "lifecycle"],
        readiness: {command: "make -C kubernetes/kind prereqs"}
      },
      {
        id: "lima",
        path: "kubernetes/lima",
        label: "lima",
        family: "local",
        class: "local-created-cluster",
        lifecycle_mode: "create",
        state_scope: "single-local",
        contexts: ["local-substrate", "platform-stack"],
        contract_outputs: ["cluster-access", "ingress", "registry", "cni", "identity", "resource-sizing", "lifecycle"],
        readiness: {command: "make -C kubernetes/lima prereqs"}
      },
      {
        id: "slicer",
        path: "kubernetes/slicer",
        label: "slicer",
        family: "local",
        class: "local-created-cluster",
        lifecycle_mode: "create",
        state_scope: "single-local",
        contexts: ["local-substrate", "platform-stack"],
        contract_outputs: ["cluster-access", "ingress", "registry", "cni", "identity", "resource-sizing", "lifecycle"],
        readiness: {command: "make -C kubernetes/slicer prereqs"}
      }
    ],
    variant_classes: [
      {
        id: "local-created-cluster",
        label: "Local created cluster",
        supported_now: true,
        lifecycle_mode: "create",
        state_scope: "single-local",
        description: "The repo creates and owns a local Kubernetes runtime."
      },
      {
        id: "attached-existing-cluster",
        label: "Attached existing cluster",
        supported_now: false,
        lifecycle_mode: "attach",
        state_scope: "external",
        description: "A future adapter consumes kubeconfig and cluster facts from outside this repo."
      },
      {
        id: "provider-managed-cluster",
        label: "Provider managed cluster",
        supported_now: false,
        lifecycle_mode: "create",
        state_scope: "per-context",
        description: "A future adapter creates a managed Kubernetes control plane behind the same platform contracts."
      },
      {
        id: "provider-infra-plus-cluster",
        label: "Provider infrastructure plus cluster",
        supported_now: false,
        lifecycle_mode: "create",
        state_scope: "per-context",
        description: "A future adapter owns network, identity, and cluster contexts separately."
      }
    ],
    contexts: [
      {
        id: "local-substrate",
        label: "Local substrate",
        state_scope: "single-local",
        lifecycle_mode: "create",
        stages: ["100"],
        provides: ["cluster-access", "ingress", "registry", "resource-sizing", "lifecycle"],
        consumes: []
      },
      {
        id: "platform-stack",
        label: "Platform stack",
        state_scope: "single-local",
        lifecycle_mode: "create",
        stages: ["200", "300", "400", "500", "600", "700", "800", "900"],
        provides: ["cni", "gitops", "apps", "observability", "identity"],
        consumes: ["cluster-access", "ingress", "registry", "resource-sizing"]
      }
    ],
    contracts: [
      {
        id: "cluster-access",
        label: "Cluster access",
        facts: ["kubeconfig_path", "kubeconfig_context", "cluster_name"],
        source: "variant_adapter"
      },
      {
        id: "ingress",
        label: "Ingress and host access",
        facts: ["public_hosts", "gateway_class", "host_access_path"],
        source: "variant_adapter"
      },
      {
        id: "registry",
        label: "Image distribution",
        facts: ["push_registry", "runtime_registry", "image_distribution_mode"],
        source: "variant_adapter"
      },
      {
        id: "cni",
        label: "Container networking",
        facts: ["cni_provider", "network_policy_provider", "hubble_available"],
        source: "platform_stack"
      },
      {
        id: "gitops",
        label: "GitOps",
        facts: ["gitops_controller", "policy_repository", "sync_model"],
        source: "platform_stack"
      },
      {
        id: "apps",
        label: "Applications",
        facts: ["enabled_apps", "custom_app_sources", "deployment_read_model"],
        source: "platform_stack"
      },
      {
        id: "observability",
        label: "Observability",
        facts: ["metrics_stack", "logs_stack", "dashboard_urls"],
        source: "platform_stack"
      },
      {
        id: "identity",
        label: "Identity",
        facts: ["identity_provider", "oidc_issuer", "session_store"],
        source: "platform_stack"
      },
      {
        id: "resource-sizing",
        label: "Resource sizing",
        facts: ["worker_count", "memory", "node_pool_shape"],
        source: "variant_adapter"
      },
      {
        id: "lifecycle",
        label: "Lifecycle",
        facts: ["lifecycle_mode", "state_scope", "rebuild_risk"],
        source: "workflow_schema"
      }
    ],
    stages: [
      {id:"100", label:"cluster", context:"local-substrate", contracts:["cluster-access", "ingress", "registry", "resource-sizing", "lifecycle"]},
      {id:"200", label:"cilium", context:"platform-stack", contracts:["cluster-access", "cni"]},
      {id:"300", label:"hubble", context:"platform-stack", contracts:["cluster-access", "cni"]},
      {id:"400", label:"argocd", context:"platform-stack", contracts:["cluster-access", "gitops"]},
      {id:"500", label:"gitea", context:"platform-stack", contracts:["cluster-access", "registry", "gitops"]},
      {id:"600", label:"policies", context:"platform-stack", contracts:["cluster-access", "cni"]},
      {id:"700", label:"app-repos", context:"platform-stack", contracts:["cluster-access", "registry", "apps"]},
      {id:"800", label:"observability", context:"platform-stack", contracts:["cluster-access", "ingress", "observability"]},
      {id:"900", label:"sso", context:"platform-stack", contracts:["cluster-access", "ingress", "identity"]}
    ],
    actions: ["readiness", "plan", "apply", "reset", "state-reset", "status", "show-urls", "check-health", "check-security", "check-rbac"],
    apps: ["sentiment", "subnetcalc"],
    status_facets: ["cluster-access", "nodes", "cni", "ingress", "gitops", "apps", "observability", "identity", "logs"],
    source_precedence: ["stage_baseline", "variant_defaults", "resource_profile", "image_distribution", "network_profile", "observability_stack", "identity_stack", "app_set", "custom_overrides"],
    external_dependency_sources: ["created_by_previous_context", "provided_by_user", "discovered", "not_applicable"],
    preset_groups: [
      {
        id: "resource_profile",
        label: "Resource profile",
        default: "default",
        merge_order: 30,
        presets: ["default", "minimal", "local-12gb", "local-idp-12gb", "airplane"]
      },
      {
        id: "image_distribution",
        label: "Image distribution",
        default: "default",
        merge_order: 40,
        presets: ["default", "pull", "local-cache", "preload", "baked", "airplane"]
      },
      {
        id: "network_profile",
        label: "Network profile",
        default: "default",
        merge_order: 50,
        presets: ["default", "cilium", "default-cni"]
      },
      {
        id: "observability_stack",
        label: "Observability stack",
        default: "default",
        merge_order: 60,
        introduced_at_stage: "800",
        presets: ["default", "victoria", "lgtm", "minimal-observability", "none"]
      },
      {
        id: "identity_stack",
        label: "Identity stack",
        default: "default",
        merge_order: 70,
        introduced_at_stage: "900",
        presets: ["default", "keycloak", "dex"]
      },
      {
        id: "app_set",
        label: "App set",
        default: "default",
        merge_order: 80,
        introduced_at_stage: "700",
        presets: ["default", "reference-apps", "no-reference-apps", "sentiment-only"]
      }
    ],
    presets: [
      {id: "default", group: "resource_profile", label: "Stage defaults", variants: ["kind", "lima", "slicer"], overlay: {}},
      {id: "minimal", group: "resource_profile", label: "Minimal", variants: ["kind", "lima", "slicer"], overlay: {enable_backstage: false, enable_prometheus: false, enable_grafana: false, enable_loki: false, enable_victoria_logs: false, enable_tempo: false}},
      {id: "local-12gb", group: "resource_profile", label: "Local 12 GB", variants: ["kind", "lima", "slicer"], overlay: {enable_backstage: false}},
      {id: "local-idp-12gb", group: "resource_profile", label: "Local IDP, 12 GB", variants: ["kind"], overlay: {enable_backstage: true, enable_prometheus: false, enable_grafana: false, enable_loki: false, enable_victoria_logs: false, enable_tempo: false, enable_app_repo_sentiment: true, enable_app_repo_subnetcalc: false}},
      {id: "airplane", group: "resource_profile", label: "Airplane", variants: ["kind", "lima", "slicer"], overlay: {enable_image_preload: true, enable_host_local_registry: true}},
      {id: "pull", group: "image_distribution", label: "Pull from upstream", variants: ["kind", "lima", "slicer"], overlay: {enable_host_local_registry: false, enable_image_preload: false}},
      {id: "local-cache", group: "image_distribution", label: "Local registry cache", variants: ["kind", "lima", "slicer"], overlay: {enable_host_local_registry: true, host_local_registry_scheme: "http"}},
      {id: "preload", group: "image_distribution", label: "Preload images", variants: ["kind"], overlay: {enable_image_preload: true}},
      {id: "baked", group: "image_distribution", label: "Baked node image", variants: ["kind"], overlay: {}},
      {id: "airplane", group: "image_distribution", label: "Airplane cache", variants: ["kind", "lima", "slicer"], overlay: {enable_host_local_registry: true, enable_image_preload: true}},
      {id: "cilium", group: "network_profile", label: "Cilium", variants: ["kind", "lima", "slicer"], overlay: {}},
      {id: "default-cni", group: "network_profile", label: "Default CNI", variants: ["slicer"], overlay: {}},
      {id: "victoria", group: "observability_stack", label: "VictoriaLogs", variants: ["kind", "lima", "slicer"], introduced_at_stage: "800", overlay: {enable_prometheus: true, enable_grafana: true, enable_victoria_logs: true, enable_loki: false, enable_tempo: false}},
      {id: "lgtm", group: "observability_stack", label: "LGTM", variants: ["kind", "lima", "slicer"], introduced_at_stage: "800", overlay: {enable_prometheus: true, enable_grafana: true, enable_loki: true, enable_tempo: true, enable_victoria_logs: false}},
      {id: "minimal-observability", group: "observability_stack", label: "Minimal observability", variants: ["kind", "lima", "slicer"], introduced_at_stage: "800", overlay: {enable_prometheus: false, enable_grafana: false, enable_loki: false, enable_victoria_logs: false, enable_tempo: false}},
      {id: "none", group: "observability_stack", label: "No optional observability", variants: ["kind", "lima", "slicer"], introduced_at_stage: "800", overlay: {enable_prometheus: false, enable_grafana: false, enable_loki: false, enable_victoria_logs: false, enable_tempo: false}},
      {id: "keycloak", group: "identity_stack", label: "Keycloak", variants: ["kind", "lima", "slicer"], introduced_at_stage: "900", overlay: {sso_provider: "keycloak"}},
      {id: "dex", group: "identity_stack", label: "Dex", variants: ["kind", "lima", "slicer"], introduced_at_stage: "900", overlay: {sso_provider: "dex"}},
      {id: "reference-apps", group: "app_set", label: "Reference apps", variants: ["kind", "lima", "slicer"], introduced_at_stage: "700", overlay: {enable_app_repo_sentiment: true, enable_app_repo_subnetcalc: true}},
      {id: "no-reference-apps", group: "app_set", label: "No reference apps", variants: ["kind", "lima", "slicer"], introduced_at_stage: "700", overlay: {enable_app_repo_sentiment: false, enable_app_repo_subnetcalc: false}},
      {id: "sentiment-only", group: "app_set", label: "Sentiment only", variants: ["kind", "lima", "slicer"], introduced_at_stage: "700", overlay: {enable_app_repo_sentiment: true, enable_app_repo_subnetcalc: false}}
    ],
    configuration_options: [
      {
        id: "worker_count",
        stage: "100",
        context: "local-substrate",
        contract: "resource-sizing",
        variants: ["kind", "lima", "slicer"],
        portability: "local-only",
        rebuild_risk: "cluster-rebuild",
        dependency_source: "not_applicable"
      },
      {
        id: "memory",
        stage: "100",
        context: "local-substrate",
        contract: "resource-sizing",
        variants: ["kind", "lima", "slicer"],
        portability: "variant-specific",
        rebuild_risk: "cluster-rebuild",
        dependency_source: "not_applicable"
      },
      {
        id: "image_distribution_mode",
        stage: "100",
        context: "local-substrate",
        contract: "registry",
        variants: ["kind", "lima", "slicer"],
        portability: "adapter-contract",
        rebuild_risk: "workload-rollout",
        dependency_source: "discovered"
      },
      {
        id: "enable_app_repo_sentiment",
        stage: "700",
        context: "platform-stack",
        contract: "apps",
        variants: ["kind", "lima", "slicer"],
        portability: "portable",
        rebuild_risk: "workload-rollout",
        dependency_source: "not_applicable"
      },
      {
        id: "enable_app_repo_subnetcalc",
        stage: "700",
        context: "platform-stack",
        contract: "apps",
        variants: ["kind", "lima", "slicer"],
        portability: "portable",
        rebuild_risk: "workload-rollout",
        dependency_source: "not_applicable"
      },
      {
        id: "observability_stack",
        stage: "800",
        context: "platform-stack",
        contract: "observability",
        variants: ["kind", "lima", "slicer"],
        portability: "portable",
        rebuild_risk: "workload-rollout",
        dependency_source: "not_applicable"
      },
      {
        id: "identity_stack",
        stage: "900",
        context: "platform-stack",
        contract: "identity",
        variants: ["kind", "lima", "slicer"],
        portability: "adapter-contract",
        rebuild_risk: "service-reconfigure",
        dependency_source: "not_applicable"
      }
    ],
    compatibility_aliases: [],
    profiles: []
  }'
}

validate_target() {
  target_path "$1" >/dev/null || die_usage "Invalid --variant '${1}'. Expected one of: kind, lima, slicer"
}

validate_stage() {
  case "${TARGET}:$1" in
    *:100|*:200|*:300|*:400|*:500|*:600|*:700|*:800|*:900) ;;
    *:950-local-idp) die_usage "Stage '950-local-idp' has been removed; use --stage 900 --preset resource-profile=local-idp-12gb" ;;
    *) die_usage "Invalid --stage '${1}'. Expected one of: 100, 200, 300, 400, 500, 600, 700, 800, 900" ;;
  esac
}

validate_action() {
  case "$1" in
    readiness|prereqs|plan|apply|reset|state-reset|status|show-urls|check-health|check-security|check-rbac) ;;
    *) die_usage "Invalid --action '${1}'. Expected one of: readiness, plan, apply, reset, state-reset, status, show-urls, check-health, check-security, check-rbac" ;;
  esac
}

action_uses_stage() {
  case "$1" in
    plan|apply|check-health|check-security|check-rbac) return 0 ;;
    readiness|prereqs|reset|state-reset|status|show-urls) return 1 ;;
    *) return 1 ;;
  esac
}

action_uses_auto_approve() {
  case "$1" in
    apply|reset|state-reset) return 0 ;;
    *) return 1 ;;
  esac
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

  if [[ "${app}" = "${spec}" || -z "${raw_value}" ]]; then
    die_usage "Invalid --app '${spec}'. Expected name=on|off"
  fi

  value="$(normalize_app_value "${raw_value}")" || die_usage "Invalid --app '${spec}'. Expected value on|off"

  case "${app}" in
    sentiment) APP_SENTIMENT="${value}" ;;
    subnetcalc) APP_SUBNETCALC="${value}" ;;
    *) die_usage "Invalid --app '${app}'. Expected one of: sentiment, subnetcalc" ;;
  esac
}

normalize_group_name() {
  printf '%s' "$1" | tr '-' '_'
}

set_preset() {
  local spec="$1"
  local raw_group="${spec%%=*}"
  local value="${spec#*=}"
  local group=""

  if [[ "${raw_group}" = "${spec}" || -z "${value}" ]]; then
    die_usage "Invalid --preset '${spec}'. Expected group=value"
  fi

  group="$(normalize_group_name "${raw_group}")"
  case "${group}:${value}" in
    resource_profile:default|resource_profile:minimal|resource_profile:local-12gb|resource_profile:local-idp-12gb|resource_profile:airplane)
      PRESET_RESOURCE_PROFILE="${value}"
      ;;
    image_distribution:default|image_distribution:pull|image_distribution:local-cache|image_distribution:preload|image_distribution:baked|image_distribution:airplane)
      PRESET_IMAGE_DISTRIBUTION="${value}"
      ;;
    network_profile:default|network_profile:cilium|network_profile:default-cni)
      PRESET_NETWORK_PROFILE="${value}"
      ;;
    observability_stack:default|observability_stack:victoria|observability_stack:lgtm|observability_stack:minimal-observability|observability_stack:none)
      PRESET_OBSERVABILITY_STACK="${value}"
      ;;
    identity_stack:default|identity_stack:keycloak|identity_stack:dex)
      PRESET_IDENTITY_STACK="${value}"
      ;;
    app_set:default|app_set:reference-apps|app_set:no-reference-apps|app_set:sentiment-only)
      PRESET_APP_SET="${value}"
      ;;
    resource_profile:*|image_distribution:*|network_profile:*|observability_stack:*|identity_stack:*|app_set:*)
      die_usage "Invalid --preset '${spec}'. Unsupported value for ${raw_group}"
      ;;
    *)
      die_usage "Invalid --preset group '${raw_group}'. Expected one of: resource-profile, image-distribution, network-profile, observability-stack, identity-stack, app-set"
      ;;
  esac
}

stage_number() {
  printf '%s' "$1"
}

stage_at_least() {
  local minimum="$1"
  local value=""

  value="$(stage_number "${STAGE}")"
  [[ "${value}" =~ ^[0-9]+$ ]] && [[ "${value}" -ge "${minimum}" ]]
}

validate_preset_selection() {
  if [[ "${PRESET_RESOURCE_PROFILE}" = "local-idp-12gb" ]]; then
    [[ "${TARGET}" = "kind" ]] || die_usage "Preset resource-profile=local-idp-12gb is only available for variant kind"
    stage_at_least 900 || die_usage "Preset resource-profile=local-idp-12gb requires stage 900 or later"
  fi
  if [[ "${PRESET_IMAGE_DISTRIBUTION}" = "preload" || "${PRESET_IMAGE_DISTRIBUTION}" = "baked" ]]; then
    [[ "${TARGET}" = "kind" ]] || die_usage "Preset image-distribution=${PRESET_IMAGE_DISTRIBUTION} is only available for variant kind"
  fi
  if [[ "${PRESET_NETWORK_PROFILE}" = "default-cni" ]]; then
    [[ "${TARGET}" = "slicer" ]] || die_usage "Preset network-profile=default-cni is only available for variant slicer"
  fi
  if [[ "${PRESET_OBSERVABILITY_STACK}" != "default" ]]; then
    stage_at_least 800 || die_usage "Preset observability-stack=${PRESET_OBSERVABILITY_STACK} requires stage 800 or later"
  fi
  if [[ "${PRESET_IDENTITY_STACK}" != "default" ]]; then
    stage_at_least 900 || die_usage "Preset identity-stack=${PRESET_IDENTITY_STACK} requires stage 900 or later"
  fi
  if [[ "${PRESET_APP_SET}" != "default" ]]; then
    stage_at_least 700 || die_usage "Preset app-set=${PRESET_APP_SET} requires stage 700 or later"
  fi
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
        keycloak|dex) printf '%s=%s' "${key}" "${raw_value}" ;;
        *) die_usage "Invalid --set '${spec}'. sso_provider must be keycloak or dex" ;;
      esac
      ;;
    enable_backstage|enable_host_local_registry|enable_image_preload|enable_prometheus|enable_grafana|enable_loki|enable_victoria_logs|enable_tempo|enable_signoz|enable_otel_gateway|enable_headlamp|enable_observability_agent|enable_app_repo_sentiment|enable_app_repo_subnetcalc|enable_actions_runner|enable_apps_dir_mount|enable_docker_socket_mount)
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
  [[ -n "${APP_SENTIMENT}" ||
    -n "${APP_SUBNETCALC}" ||
    "${PRESET_RESOURCE_PROFILE}" != "default" ||
    "${PRESET_IMAGE_DISTRIBUTION}" != "default" ||
    "${PRESET_OBSERVABILITY_STACK}" != "default" ||
    "${PRESET_IDENTITY_STACK}" != "default" ||
    "${PRESET_APP_SET}" != "default" ||
    "${#CUSTOM_OVERRIDES[@]}" -gt 0 ]]
}

local_registry_runtime_host() {
  case "${TARGET}" in
    kind) printf 'host.docker.internal:5002' ;;
    lima) printf 'host.lima.internal:5002' ;;
    slicer) printf '192.168.64.1:5002' ;;
    *) return 1 ;;
  esac
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

render_local_idp_12gb_overlay() {
  local registry_host=""

  registry_host="$(local_registry_runtime_host)"
  render_assignment enable_argocd true "preset resource-profile=local-idp-12gb"
  render_assignment enable_gitea true "preset resource-profile=local-idp-12gb"
  render_assignment enable_gateway_tls true "preset resource-profile=local-idp-12gb"
  render_assignment enable_cert_manager true "preset resource-profile=local-idp-12gb"
  render_assignment enable_sso true "preset resource-profile=local-idp-12gb"
  render_assignment sso_provider keycloak "preset resource-profile=local-idp-12gb"
  render_assignment enable_argocd_oidc true "preset resource-profile=local-idp-12gb"
  render_assignment enable_app_of_apps false "preset resource-profile=local-idp-12gb"
  render_assignment argocd_applicationset_enabled false "preset resource-profile=local-idp-12gb"
  render_assignment argocd_notifications_enabled false "preset resource-profile=local-idp-12gb"
  render_assignment enable_app_repo_sentiment true "preset resource-profile=local-idp-12gb"
  render_assignment enable_app_repo_subnetcalc false "preset resource-profile=local-idp-12gb"
  render_assignment enable_backstage true "preset resource-profile=local-idp-12gb"
  render_assignment enable_host_local_registry true "preset resource-profile=local-idp-12gb"
  render_assignment host_local_registry_host "${registry_host}" "preset resource-profile=local-idp-12gb"
  render_assignment host_local_registry_scheme http "preset resource-profile=local-idp-12gb"
  render_assignment prefer_external_platform_images true "preset resource-profile=local-idp-12gb"
  render_assignment prefer_external_workload_images true "preset resource-profile=local-idp-12gb"
  render_assignment enable_actions_runner false "preset resource-profile=local-idp-12gb"
  render_assignment enable_apps_dir_mount false "preset resource-profile=local-idp-12gb"
  render_assignment enable_docker_socket_mount false "preset resource-profile=local-idp-12gb"
  cat <<EOF
# Source: preset resource-profile=local-idp-12gb
external_platform_image_refs = {
  "backstage" = "${registry_host}/platform/backstage:latest"
  "idp-core" = "${registry_host}/platform/idp-core:latest"
}

# Source: preset resource-profile=local-idp-12gb
external_workload_image_refs = {
  "sentiment-api" = "${registry_host}/platform/sentiment-api:latest"
  "sentiment-auth-ui" = "${registry_host}/platform/sentiment-auth-ui:latest"
}

EOF
  render_assignment enable_signoz false "preset resource-profile=local-idp-12gb"
  render_assignment enable_prometheus false "preset resource-profile=local-idp-12gb"
  render_assignment enable_grafana false "preset resource-profile=local-idp-12gb"
  render_assignment enable_loki false "preset resource-profile=local-idp-12gb"
  render_assignment enable_victoria_logs false "preset resource-profile=local-idp-12gb"
  render_assignment enable_tempo false "preset resource-profile=local-idp-12gb"
  render_assignment enable_observability_agent false "preset resource-profile=local-idp-12gb"
  render_assignment enable_headlamp false "preset resource-profile=local-idp-12gb"
}

render_preset_tfvars() {
  local registry_host=""

  case "${PRESET_RESOURCE_PROFILE}" in
    minimal)
      render_assignment enable_backstage false "preset resource-profile=minimal"
      render_assignment enable_prometheus false "preset resource-profile=minimal"
      render_assignment enable_grafana false "preset resource-profile=minimal"
      render_assignment enable_loki false "preset resource-profile=minimal"
      render_assignment enable_victoria_logs false "preset resource-profile=minimal"
      render_assignment enable_tempo false "preset resource-profile=minimal"
      ;;
    local-12gb)
      render_assignment enable_backstage false "preset resource-profile=local-12gb"
      ;;
    local-idp-12gb)
      render_local_idp_12gb_overlay
      ;;
    airplane)
      render_assignment enable_image_preload true "preset resource-profile=airplane"
      render_assignment enable_host_local_registry true "preset resource-profile=airplane"
      render_assignment host_local_registry_scheme http "preset resource-profile=airplane"
      render_assignment host_local_registry_host "$(local_registry_runtime_host)" "preset resource-profile=airplane"
      ;;
    default) ;;
  esac

  case "${PRESET_IMAGE_DISTRIBUTION}" in
    pull)
      render_assignment enable_host_local_registry false "preset image-distribution=pull"
      render_assignment enable_image_preload false "preset image-distribution=pull"
      ;;
    local-cache)
      registry_host="$(local_registry_runtime_host)"
      render_assignment enable_host_local_registry true "preset image-distribution=local-cache"
      render_assignment host_local_registry_host "${registry_host}" "preset image-distribution=local-cache"
      render_assignment host_local_registry_scheme http "preset image-distribution=local-cache"
      ;;
    preload)
      render_assignment enable_image_preload true "preset image-distribution=preload"
      ;;
    airplane)
      registry_host="$(local_registry_runtime_host)"
      render_assignment enable_host_local_registry true "preset image-distribution=airplane"
      render_assignment enable_image_preload true "preset image-distribution=airplane"
      render_assignment host_local_registry_host "${registry_host}" "preset image-distribution=airplane"
      render_assignment host_local_registry_scheme http "preset image-distribution=airplane"
      ;;
    baked|default) ;;
  esac

  case "${PRESET_OBSERVABILITY_STACK}" in
    victoria)
      render_assignment enable_prometheus true "preset observability-stack=victoria"
      render_assignment enable_grafana true "preset observability-stack=victoria"
      render_assignment enable_victoria_logs true "preset observability-stack=victoria"
      render_assignment enable_loki false "preset observability-stack=victoria"
      render_assignment enable_tempo false "preset observability-stack=victoria"
      ;;
    lgtm)
      render_assignment enable_prometheus true "preset observability-stack=lgtm"
      render_assignment enable_grafana true "preset observability-stack=lgtm"
      render_assignment enable_loki true "preset observability-stack=lgtm"
      render_assignment enable_tempo true "preset observability-stack=lgtm"
      render_assignment enable_victoria_logs false "preset observability-stack=lgtm"
      ;;
    minimal-observability|none)
      render_assignment enable_prometheus false "preset observability-stack=${PRESET_OBSERVABILITY_STACK}"
      render_assignment enable_grafana false "preset observability-stack=${PRESET_OBSERVABILITY_STACK}"
      render_assignment enable_loki false "preset observability-stack=${PRESET_OBSERVABILITY_STACK}"
      render_assignment enable_victoria_logs false "preset observability-stack=${PRESET_OBSERVABILITY_STACK}"
      render_assignment enable_tempo false "preset observability-stack=${PRESET_OBSERVABILITY_STACK}"
      ;;
    default) ;;
  esac

  case "${PRESET_IDENTITY_STACK}" in
    keycloak|dex)
      render_assignment sso_provider "${PRESET_IDENTITY_STACK}" "preset identity-stack=${PRESET_IDENTITY_STACK}"
      ;;
    default) ;;
  esac

  case "${PRESET_APP_SET}" in
    reference-apps)
      render_assignment enable_app_repo_sentiment true "preset app-set=reference-apps"
      render_assignment enable_app_repo_subnetcalc true "preset app-set=reference-apps"
      ;;
    no-reference-apps)
      render_assignment enable_app_repo_sentiment false "preset app-set=no-reference-apps"
      render_assignment enable_app_repo_subnetcalc false "preset app-set=no-reference-apps"
      ;;
    sentiment-only)
      render_assignment enable_app_repo_sentiment true "preset app-set=sentiment-only"
      render_assignment enable_app_repo_subnetcalc false "preset app-set=sentiment-only"
      ;;
    default) ;;
  esac
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
  printf '# Generated by scripts/platform-workflow.sh; safe to delete.\n'
  printf '# Variant: %s, stage: %s\n' "${TARGET}" "${STAGE}"
  printf '\n'
  render_preset_tfvars
  if [[ -n "${APP_SENTIMENT}" ]]; then
    render_assignment enable_app_repo_sentiment "${APP_SENTIMENT}" "custom app override"
  fi
  if [[ -n "${APP_SUBNETCALC}" ]]; then
    render_assignment enable_app_repo_subnetcalc "${APP_SUBNETCALC}" "custom app override"
  fi
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
        lima|slicer)
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
          append_env_override "KIND_LOCAL_IMAGE_CACHE_PUSH_HOST=127.0.0.1:5002"
          ;;
        lima|slicer)
          append_env_override "PLATFORM_LOCAL_IMAGE_CACHE_MODE=on"
          append_env_override "LOCAL_IMAGE_CACHE_HOST=$(local_registry_runtime_host)"
          append_env_override "LOCAL_IMAGE_CACHE_PUSH_HOST=127.0.0.1:5002"
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
          append_env_override "KIND_LOCAL_IMAGE_CACHE_PUSH_HOST=127.0.0.1:5002"
          append_env_override "KIND_LOCAL_IMAGE_CACHE_OPTIONAL=0"
          ;;
        lima|slicer)
          append_env_override "PLATFORM_LOCAL_IMAGE_CACHE_MODE=on"
          append_env_override "PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=on"
          append_env_override "PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=on"
          append_env_override "LOCAL_IMAGE_CACHE_HOST=$(local_registry_runtime_host)"
          append_env_override "LOCAL_IMAGE_CACHE_PUSH_HOST=127.0.0.1:5002"
          append_env_override "LOCAL_IMAGE_CACHE_OPTIONAL=0"
          ;;
      esac
      ;;
    default) ;;
  esac
}

append_network_profile_env() {
  case "${PRESET_NETWORK_PROFILE}" in
    cilium)
      if [[ "${TARGET}" = "slicer" ]]; then
        append_env_override "SLICER_NETWORK_PROFILE=cilium"
      fi
      ;;
    default-cni)
      append_env_override "SLICER_NETWORK_PROFILE=default"
      ;;
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

print_options() {
  case "${OUTPUT_FORMAT}" in
    text)
      cat <<'EOF'
Variants:
  kind    local-created-cluster  kubernetes/kind
  lima    local-created-cluster  kubernetes/lima
  slicer  local-created-cluster  kubernetes/slicer

Variant classes:
  local-created-cluster          supported now
  attached-existing-cluster      future adapter contract
  provider-managed-cluster       future adapter contract
  provider-infra-plus-cluster    future adapter contract

Stages:
  100 cluster
  200 cilium
  300 hubble
  400 argocd
  500 gitea
  600 policies
  700 app-repos
  800 observability
  900 sso

Actions:
  readiness
  plan
  apply
  status
  show-urls
  reset
  state-reset
  check-health
  check-security
  check-rbac

App toggles:
  sentiment=on|off
  subnetcalc=on|off

Preset groups:
  resource-profile=default|minimal|local-12gb|local-idp-12gb|airplane
  image-distribution=default|pull|local-cache|preload|baked|airplane
  network-profile=default|cilium|default-cni
  observability-stack=default|victoria|lgtm|minimal-observability|none
  identity-stack=default|keycloak|dex
  app-set=default|reference-apps|no-reference-apps|sentiment-only

Custom overrides:
  --set worker_count=2
  --set enable_backstage=off
  --set enable_app_repo_subnetcalc=off

EOF
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
        --argjson app_sentiment "$(if [[ -n "${APP_SENTIMENT}" ]]; then printf '%s' "${APP_SENTIMENT}"; else printf null; fi)" \
        --argjson app_subnetcalc "$(if [[ -n "${APP_SUBNETCALC}" ]]; then printf '%s' "${APP_SUBNETCALC}"; else printf null; fi)" \
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
          app_overrides: {
            sentiment: $app_sentiment,
            subnetcalc: $app_subnetcalc
          },
          command: $command
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
      die_usage "--profile has been removed; use --preset resource-profile=local-idp-12gb when you need the local IDP resource profile"
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

validate_target "${TARGET}"
validate_stage "${STAGE}"
validate_action "${ACTION}"
validate_preset_selection

if [[ -z "${TFVARS_FILE}" ]]; then
  TFVARS_FILE="$(default_tfvars_file)"
fi

STACK_PATH="$(target_path "${TARGET}")"
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
