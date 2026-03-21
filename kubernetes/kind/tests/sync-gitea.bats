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
  run bash -lc "source '${SCRIPT}'; resolve_string SIGNOZ_CHART_VERSION signoz_chart_version \"\$(tf_default_from_variables signoz_chart_version)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "0.116.2" ]
}

@test "sync-gitea.sh falls back to Terraform variable defaults when tfvars are absent" {
  missing_tfvars="${BATS_TEST_TMPDIR}/missing.tfvars"

  run bash -lc "export GITEA_SYNC_TFVARS_FILE='${missing_tfvars}'; source '${SCRIPT}'; resolve_string SIGNOZ_CHART_VERSION signoz_chart_version \"\$(tf_default_from_variables signoz_chart_version)\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "0.116.2" ]
}
