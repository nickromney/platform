#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SSO_FILE="${REPO_ROOT}/terraform/kubernetes/sso.tf"
}

@test "kind OIDC apply waits for cluster health after the apiserver patch" {
  run grep -Fn 'resource "null_resource" "check_kind_cluster_health_after_oidc"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'oidc_resource_id[[:space:]]*=[[:space:]]*null_resource\.configure_kind_apiserver_oidc\[0\]\.id' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'check-cluster-health.sh' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'operator_overrides_sha = try(filesha256(abspath("${path.module}/../../.run/kind/operator-overrides.tfvars")), "absent")' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'KIND_OPERATOR_OVERRIDES_FILE="${abspath("${path.module}/../../.run/kind/operator-overrides.tfvars")}"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn -- '--var-file "$${KIND_OPERATOR_OVERRIDES_FILE}"' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'null_resource.check_kind_cluster_health_after_oidc,' "${SSO_FILE}"

  [ "${status}" -eq 0 ]
}
