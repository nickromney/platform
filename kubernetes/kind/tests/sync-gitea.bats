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
  expected="$(bash -lc "source '${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh'; tf_default_from_variables agentgateway_chart_version")"

  run bash -lc "source '${SCRIPT}'; resolve_string AGENTGATEWAY_CHART_VERSION agentgateway_chart_version \"\$(tf_default_from_variables agentgateway_chart_version)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "${expected}" ]
}

@test "sync-gitea.sh falls back to Terraform variable defaults when tfvars are absent" {
  missing_tfvars="${BATS_TEST_TMPDIR}/missing.tfvars"
  expected="$(bash -lc "source '${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh'; tf_default_from_variables agentgateway_chart_version")"

  run bash -lc "export GITEA_SYNC_TFVARS_FILE='${missing_tfvars}'; source '${SCRIPT}'; resolve_string AGENTGATEWAY_CHART_VERSION agentgateway_chart_version \"\$(tf_default_from_variables agentgateway_chart_version)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "${expected}" ]
}

@test "sync-gitea.sh exports every platform image override consumed by the policies renderer" {
  run grep -Fn 'export_external_platform_image EXTERNAL_PLATFORM_IMAGE_CHATGPT_SIM chatgpt-sim' "${SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "sync-gitea.sh reads map string values from target tfvars" {
  target_tfvars="${BATS_TEST_TMPDIR}/target.tfvars"
  cat >"${target_tfvars}" <<'EOF'
external_platform_image_refs = {
  "idp-core" = "host.docker.internal:5002/platform/idp-core:target"
}
EOF

  run bash -lc "source '${SCRIPT}'; tfvar_map_string_or_default '${target_tfvars}' external_platform_image_refs idp-core missing"

  [ "${status}" -eq 0 ]
  [ "${output}" = "host.docker.internal:5002/platform/idp-core:target" ]
}

@test "sync-gitea.sh lets target tfvars override stage booleans for local kind toggles" {
  stage_tfvars="${BATS_TEST_TMPDIR}/stage.tfvars"
  target_tfvars="${BATS_TEST_TMPDIR}/target.tfvars"
  cat >"${stage_tfvars}" <<'EOF'
enable_actions_runner = true
enable_backstage = true
EOF
  cat >"${target_tfvars}" <<'EOF'
enable_actions_runner = false
enable_backstage = false
EOF

  run bash -lc "export GITEA_SYNC_TFVARS_FILE='${stage_tfvars}' GITEA_SYNC_TARGET_TFVARS_FILE='${target_tfvars}'; source '${SCRIPT}'; printf '%s\n' \"\$(resolve_bool_target_or_stage ENABLE_ACTIONS_RUNNER enable_actions_runner true)\" \"\$(resolve_bool_target_or_stage ENABLE_BACKSTAGE enable_backstage true)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'false\nfalse')" ]
}

@test "sync-gitea.sh exports local kind toggles from target-or-stage inputs" {
  run bash -lc "grep -F 'export_resolved_bool_target_or_stage ENABLE_ACTIONS_RUNNER enable_actions_runner true' '${SCRIPT}' && grep -F 'export_resolved_bool_target_or_stage ENABLE_BACKSTAGE enable_backstage true' '${SCRIPT}'"

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
