#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/sync-gitea.sh"
  export DEFAULT_STAGE_TFVARS="${REPO_ROOT}/kubernetes/kind/stages/900-sso.tfvars"
}

@test "sync-gitea.sh defaults to the kind stage tfvars file" {
  run bash -lc "source '${SCRIPT}'; printf '%s\n' \"\$GITEA_SYNC_TFVARS_FILE\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "${DEFAULT_STAGE_TFVARS}" ]
}

@test "sync-gitea.sh uses Terraform variable defaults when stage tfvars omit a chart version" {

  [ "${status}" -eq 0 ]
  [ "${output}" = "0.120.0" ]
}

@test "sync-gitea.sh falls back to Terraform variable defaults when tfvars are absent" {
  missing_tfvars="${BATS_TEST_TMPDIR}/missing.tfvars"


  [ "${status}" -eq 0 ]
  [ "${output}" = "0.120.0" ]
}

@test "sync-gitea.sh exports every platform image override consumed by the policies renderer" {
  run grep -Fn 'export_external_platform_image EXTERNAL_PLATFORM_IMAGE_CHATGPT_SIM chatgpt-sim' "${SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "sync-gitea.sh exports agentgateway GitOps inputs consumed by the policies renderer" {
  run bash -lc "grep -F 'export_resolved_bool ENABLE_AGENTGATEWAY_AI_GATEWAY enable_agentgateway_ai_gateway false' '${SCRIPT}' && grep -F 'export_resolved_string AGENTGATEWAY_CHART_VERSION agentgateway_chart_version' '${SCRIPT}' && grep -F 'export_resolved_string AGENTGATEWAY_AI_GATEWAY_MODEL agentgateway_ai_gateway_model' '${SCRIPT}'"

  [ "${status}" -eq 0 ]
}

@test "sync-gitea.sh exports SSO so stage 900 keeps SSO gateway routes" {
  run grep -Fn 'export_resolved_bool ENABLE_SSO enable_sso false' "${SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "sync-gitea.sh exports Headlamp OIDC inputs consumed by the policies renderer" {
  run bash -lc "grep -F 'export_resolved_string SSO_PUBLIC_URL sso_public_url' '${SCRIPT}' && grep -F 'export_resolved_string HEADLAMP_PUBLIC_HOST headlamp_public_host' '${SCRIPT}' && grep -F 'export_resolved_string HEADLAMP_OIDC_CLIENT_SECRET headlamp_oidc_client_secret' '${SCRIPT}' && grep -F 'export_resolved_bool HEADLAMP_OIDC_SKIP_TLS_VERIFY headlamp_oidc_skip_tls_verify true' '${SCRIPT}'"

  [ "${status}" -eq 0 ]
}

@test "sync-gitea.sh passes the Terraform render contract to the policies renderer when present" {
  run grep -Fn 'GITOPS_RENDER_CONTRACT_FILE="${GITOPS_RENDER_CONTRACT_FILE:-${STACK_DIR}/.run/kind/gitops-render-contract.json}"' "${SCRIPT}"

  [ "${status}" -eq 0 ]
}
