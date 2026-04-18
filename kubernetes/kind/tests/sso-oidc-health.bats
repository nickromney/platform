#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SSO_FILE="${REPO_ROOT}/terraform/kubernetes/sso.tf"
}

@test "kind OIDC apply models post-restart recovery as an explicit step between patching and cluster health" {
  run grep -Fn 'resource "null_resource" "recover_kind_cluster_after_oidc_restart"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'oidc_resource_id[[:space:]]*=[[:space:]]*null_resource\.configure_kind_apiserver_oidc\[0\]\.id' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'recover-kind-cluster-after-apiserver-restart.sh' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'null_resource.recover_kind_cluster_after_oidc_restart,' "${SSO_FILE}"

  [ "${status}" -eq 0 ]
}

@test "kind OIDC apply waits for cluster health after the explicit post-restart recovery step" {
  run grep -Fn 'resource "null_resource" "check_kind_cluster_health_after_oidc"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'recovery_resource_id[[:space:]]*=[[:space:]]*null_resource\.recover_kind_cluster_after_oidc_restart\[0\]\.id' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'check-cluster-health.sh' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'kind_stage_900_tfvars_sha[[:space:]]*=[[:space:]]*try\(filesha256\(var\.kind_stage_900_tfvars_file\), "absent"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'kind_target_tfvars_sha[[:space:]]*=[[:space:]]*try\(filesha256\(var\.kind_target_tfvars_file\), "absent"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'operator_overrides_sha[[:space:]]*=[[:space:]]*try\(filesha256\(var\.kind_operator_overrides_file\), "absent"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'KIND_STAGE_900_TFVARS_FILE="${var.kind_stage_900_tfvars_file}"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'KIND_TARGET_TFVARS_FILE="${var.kind_target_tfvars_file}"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'KIND_OPERATOR_OVERRIDES_FILE="${var.kind_operator_overrides_file}"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn -- '--var-file "$${KIND_OPERATOR_OVERRIDES_FILE}"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'null_resource.check_kind_cluster_health_after_oidc,' "${SSO_FILE}"

  [ "${status}" -eq 0 ]
}
