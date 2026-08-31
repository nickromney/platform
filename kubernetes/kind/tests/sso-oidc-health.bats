#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SSO_FILE="${REPO_ROOT}/terraform/kubernetes/sso.tf"
  export AFTER_OIDC_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health-after-oidc.sh"
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

  run grep -E -n 'kind_stage_tfvars_sha[[:space:]]*=[[:space:]]*try\(filesha256\(var\.kind_stage_tfvars_file\), "absent"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'kind_target_tfvars_sha[[:space:]]*=[[:space:]]*try\(filesha256\(var\.kind_target_tfvars_file\), "absent"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'operator_overrides_sha[[:space:]]*=[[:space:]]*try\(filesha256\(var\.kind_operator_overrides_file\), "absent"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'KIND_STAGE_TFVARS_FILE[[:space:]]*=[[:space:]]*var\.kind_stage_tfvars_file' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'KIND_TARGET_TFVARS_FILE[[:space:]]*=[[:space:]]*var\.kind_target_tfvars_file' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'KIND_OPERATOR_OVERRIDES_FILE[[:space:]]*=[[:space:]]*var\.kind_operator_overrides_file' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  # The var-file assembly moved into the extracted script; PLATFORM_TFVARS is
  # still inherited from the process environment rather than passed explicitly.
  run grep -Fn -- '--var-file "${KIND_STAGE_TFVARS_FILE}"' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -Fn -- '--var-file "${KIND_OPERATOR_OVERRIDES_FILE}"' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'null_resource.check_kind_cluster_health_after_oidc,' "${SSO_FILE}"

  [ "${status}" -eq 0 ]
}

@test "kind OIDC health local-exec delegates to the extracted script" {
  run grep -Fn 'scripts/check-cluster-health-after-oidc.sh' "${SSO_FILE}"

  [ "${status}" -eq 0 ]

  run grep -E -n 'after_oidc_script_sha[[:space:]]*=[[:space:]]*filesha256\("\$\{local\.stack_dir\}/scripts/check-cluster-health-after-oidc\.sh"\)' "${SSO_FILE}"

  [ "${status}" -eq 0 ]
}

@test "kind OIDC health provisioner retries once after a failed post-restart health check" {
  run grep -Fn 'for attempt in 1 2; do' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]

  # The 60s wait is now a default rather than a literal, so assert both halves:
  # a bare 'sleep 60' grep would go quiet the moment it was parameterised.
  run grep -Fn 'RETRY_SLEEP_SECONDS="${RETRY_SLEEP_SECONDS:-60}"' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'Post-OIDC cluster health check failed; retrying once in ${RETRY_SLEEP_SECONDS}s...' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'sleep "${RETRY_SLEEP_SECONDS}"' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -Fn 'exit 1' "${AFTER_OIDC_SCRIPT}"

  [ "${status}" -eq 0 ]
}

# The post-OIDC health check runs from a Terraform local-exec, so it assembles
# its own --var-file list rather than inheriting the Makefile's. Any tfvars
# source missing from that list is invisible to the check, and an app the
# operator profile disables then reads as missing rather than as not requested.
setup_after_oidc_harness() {
  after_oidc_script="${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health-after-oidc.sh"
  work="${BATS_TEST_TMPDIR}"

  for f in stage target profile platform operator; do
    printf '# %s\n' "$f" >"${work}/${f}.tfvars"
  done

  # Stands in for check-cluster-health.sh and records the arguments it was given.
  cat >"${work}/fake-health.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${ARGS_OUT}"
exit 0
EOF
  chmod +x "${work}/fake-health.sh"
}

@test "the post-OIDC health check passes the operator profile tfvars" {
  setup_after_oidc_harness

  run env \
    HEALTH_SCRIPT="${work}/fake-health.sh" \
    ARGS_OUT="${work}/args.txt" \
    KUBECONFIG="${work}/kubeconfig" \
    KIND_STAGE_TFVARS_FILE="${work}/stage.tfvars" \
    KIND_TARGET_TFVARS_FILE="${work}/target.tfvars" \
    KIND_PROFILE_TFVARS_FILE="${work}/profile.tfvars" \
    PLATFORM_TFVARS="${work}/platform.tfvars" \
    KIND_OPERATOR_OVERRIDES_FILE="${work}/operator.tfvars" \
    bash "${after_oidc_script}" --execute

  [ "${status}" -eq 0 ]
  run cat "${work}/args.txt"
  [[ "${output}" == *"profile.tfvars"* ]]
}

@test "the post-OIDC health check orders the profile between target and platform" {
  setup_after_oidc_harness

  env \
    HEALTH_SCRIPT="${work}/fake-health.sh" \
    ARGS_OUT="${work}/args.txt" \
    KUBECONFIG="${work}/kubeconfig" \
    KIND_STAGE_TFVARS_FILE="${work}/stage.tfvars" \
    KIND_TARGET_TFVARS_FILE="${work}/target.tfvars" \
    KIND_PROFILE_TFVARS_FILE="${work}/profile.tfvars" \
    PLATFORM_TFVARS="${work}/platform.tfvars" \
    KIND_OPERATOR_OVERRIDES_FILE="${work}/operator.tfvars" \
    bash "${after_oidc_script}" --execute

  # Later files win, so the order is the precedence the Makefile builds.
  run bash -c "grep -n 'tfvars' '${work}/args.txt' | tr '\n' ' '"
  [[ "${output}" =~ stage.*target.*profile.*platform.*operator ]]
}

@test "the post-OIDC health check omits tfvars sources that are not set" {
  setup_after_oidc_harness

  run env \
    HEALTH_SCRIPT="${work}/fake-health.sh" \
    ARGS_OUT="${work}/args.txt" \
    KUBECONFIG="${work}/kubeconfig" \
    KIND_STAGE_TFVARS_FILE="${work}/stage.tfvars" \
    bash "${after_oidc_script}" --execute

  [ "${status}" -eq 0 ]
  run cat "${work}/args.txt"
  [[ "${output}" == *"stage.tfvars"* ]]
  [[ "${output}" != *"profile.tfvars"* ]]
}
