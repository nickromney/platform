#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF >&2
Usage: ${0##*/} [--dry-run] [--execute]

Annotates kind apply output with coarse phase progress lines.

$(shell_cli_standard_options)
EOF
}

emit_phase() {
  local phase="$1"
  local label="$2"

  case "${phase}" in
    1)
      [[ "${PHASE_1_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_1_PRINTED=1
      ;;
    2)
      [[ "${PHASE_2_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_2_PRINTED=1
      ;;
    3)
      [[ "${PHASE_3_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_3_PRINTED=1
      ;;
    4)
      [[ "${PHASE_4_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_4_PRINTED=1
      ;;
    5)
      [[ "${PHASE_5_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_5_PRINTED=1
      ;;
    6)
      [[ "${PHASE_6_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_6_PRINTED=1
      ;;
    7)
      [[ "${PHASE_7_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_7_PRINTED=1
      ;;
    8)
      [[ "${PHASE_8_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_8_PRINTED=1
      ;;
    9)
      [[ "${PHASE_9_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_9_PRINTED=1
      ;;
    10)
      [[ "${PHASE_10_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_10_PRINTED=1
      ;;
    11)
      [[ "${PHASE_11_PRINTED:-0}" -eq 0 ]] || return 0
      PHASE_11_PRINTED=1
      ;;
    *)
      return 0
      ;;
  esac

  printf 'PHASE %s/11: %s\n' "${phase}" "${label}"
}

annotate_line() {
  local line="$1"

  case "${line}" in
    *'run_step "build-local-platform-images"'*|*'run_step "build-local-workload-images"'*|*'build-local-platform-images'*|*'build-local-workload-images'*|*'null_resource.preload_images'*)
      emit_phase 1 "Prereqs and local image build (typically 1-2m)"
      ;;
    *'terragrunt apply'*|*'tofu apply'*|*'OpenTofu'*|*'Terraform will perform the following actions'*)
      emit_phase 2 "OpenTofu apply planning (typically seconds)"
      ;;
    *'helm_release.cilium'*|*'null_resource.cilium_restart_on_config_change'*)
      emit_phase 3 "Cilium install (typically <1m)"
      ;;
    *'helm_release.argocd'*)
      emit_phase 4 "Argo CD install (typically <1m)"
      ;;
    *'kubectl_manifest.argocd_app_gitea'*|*'null_resource.gitea_promote_admin'*|*'null_resource.gitea_org'*|*'null_resource.gitea_unset_must_change_password'*)
      emit_phase 5 "Gitea bootstrap (typically ~1m)"
      ;;
    *'null_resource.sync_gitea_policies_repo'*)
      emit_phase 6 "Policies repo sync (typically <1m)"
      ;;
    *'kubectl_manifest.argocd_app_of_apps'*|*'null_resource.argocd_refresh_gitops_repo_apps'*)
      emit_phase 7 "App-of-apps sync (typically <1m)"
      ;;
    *'kubectl_manifest.keycloak'*|*'null_resource.reconcile_keycloak_realm'*)
      emit_phase 8 "Keycloak deployment (typically 1-2m)"
      ;;
    *'null_resource.wait_for_platform_gateway_tls'*|*'kubectl_manifest.argocd_app_cert_manager'*|*'kubectl_manifest.argocd_app_platform_gateway'*)
      emit_phase 9 "cert-manager and gateway TLS wait (typically 1-3m)"
      ;;
    *'null_resource.configure_kind_apiserver_oidc'*|*'null_resource.recover_kind_cluster_after_oidc_restart'*|*'null_resource.check_kind_cluster_health_after_oidc'*)
      emit_phase 10 "API server OIDC and post-OIDC health (typically 1-3m)"
      ;;
    *'post-apply-verification'*|*'check-health'*|*'check-gateway-urls'*|*'check-sso-e2e'*)
      emit_phase 11 "Post-apply verification and E2E (typically ~1m)"
      ;;
  esac

  printf '%s\n' "${line}"
}

annotate_stream() {
  local line=""

  if [[ "${KIND_APPLY_PROGRESS:-1}" == "0" ]]; then
    cat
    return 0
  fi

  while IFS= read -r line || [[ -n "${line}" ]]; do
    annotate_line "${line}"
  done
}

main() {
  shell_cli_handle_standard_no_args usage "would annotate kind apply progress lines from stdin" "$@"
  annotate_stream
}

main "$@"
