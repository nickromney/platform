#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/plan-post-apply-verification.sh"
}

write_tfvars() {
  local path="$1"
  shift
  printf '%s\n' "$@" >"${path}"
}

@test "variant apply recipes delegate post-apply verification policy to the shared planner" {
  for variant in kind lima slicer; do
    makefile="${REPO_ROOT}/kubernetes/${variant}/Makefile"
    grep -Fq 'PLAN_POST_APPLY_VERIFICATION :=' "${makefile}"
    grep -Fq 'RUN_POST_APPLY_VERIFICATION :=' "${makefile}"
    grep -Fq 'post_apply_plan="$$( "$(PLAN_POST_APPLY_VERIFICATION)" --execute --variant-json "$(VARIANT_JSON)" --stage "$(STAGE)" "$${post_apply_args[@]}" )"' "${makefile}"
    grep -Fq 'run_step "post-apply-verification" "$(RUN_POST_APPLY_VERIFICATION)" --execute --variant-json "$(VARIANT_JSON)" --stage "$(STAGE)" --make-dir "$(abspath $(MAKEFILE_DIR))" <<< "$$post_apply_plan"' "${makefile}"
    ! grep -Fq 'Unknown post-apply verification step:' "${makefile}"
  done

  ! grep -Fq 'enable_gateway_tls="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/kind/Makefile"
  ! grep -Fq 'enable_headlamp="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/kind/Makefile"
  ! grep -Fq 'enable_gateway_tls="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/lima/Makefile"
  ! grep -Fq 'enable_headlamp="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/lima/Makefile"
  ! grep -Fq 'enable_sso="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/lima/Makefile"
  ! grep -Fq 'enable_gateway_tls="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/slicer/Makefile"
  ! grep -Fq 'enable_headlamp="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/slicer/Makefile"
  ! grep -Fq 'enable_sso="$$( "$(RESOLVE_TFVAR_VALUE)"' "${REPO_ROOT}/kubernetes/slicer/Makefile"
}

@test "post-apply verification plan is sourced from variant contract and tfvars" {
  base_tfvars="${BATS_TEST_TMPDIR}/base.tfvars"
  override_tfvars="${BATS_TEST_TMPDIR}/override.tfvars"
  write_tfvars "${base_tfvars}" \
    'enable_gateway_tls = true' \
    'enable_headlamp = false' \
    'enable_sso = false'
  write_tfvars "${override_tfvars}" \
    'enable_headlamp = true' \
    'enable_sso = true'

  run "${SCRIPT}" --execute \
    --variant-json "${REPO_ROOT}/kubernetes/variants/kind/variant.json" \
    --stage 900 \
    --var-file "${base_tfvars}" \
    --var-file "${override_tfvars}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'check-health\ncheck-gateway-urls\ncheck-sso-e2e' ]

  run "${SCRIPT}" --execute \
    --variant-json "${REPO_ROOT}/kubernetes/variants/lima/variant.json" \
    --stage 900 \
    --var-file "${base_tfvars}" \
    --var-file "${override_tfvars}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'configure-k3s-apiserver-oidc\ncheck-health\ncheck-gateway-urls\ncheck-sso-e2e' ]

  run "${SCRIPT}" --execute \
    --variant-json "${REPO_ROOT}/kubernetes/variants/slicer/variant.json" \
    --stage 900 \
    --var-file "${base_tfvars}" \
    --var-file "${override_tfvars}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'configure-k3s-apiserver-oidc\ncheck-health\ncheck-gateway-urls\ncheck-sso-e2e' ]
}

@test "post-apply verification plan preserves stage and feature gates" {
  enabled_tfvars="${BATS_TEST_TMPDIR}/enabled.tfvars"
  disabled_tfvars="${BATS_TEST_TMPDIR}/disabled.tfvars"
  write_tfvars "${enabled_tfvars}" \
    'enable_gateway_tls = true' \
    'enable_headlamp = true' \
    'enable_sso = true'
  write_tfvars "${disabled_tfvars}" \
    'enable_gateway_tls = false' \
    'enable_headlamp = true' \
    'enable_sso = true'

  run "${SCRIPT}" --execute \
    --variant-json "${REPO_ROOT}/kubernetes/variants/kind/variant.json" \
    --stage 800 \
    --var-file "${enabled_tfvars}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'check-health\ncheck-gateway-urls' ]

  run "${SCRIPT}" --execute \
    --variant-json "${REPO_ROOT}/kubernetes/variants/lima/variant.json" \
    --stage 800 \
    --var-file "${enabled_tfvars}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]

  run "${SCRIPT}" --execute \
    --variant-json "${REPO_ROOT}/kubernetes/variants/kind/variant.json" \
    --stage 900 \
    --var-file "${disabled_tfvars}"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
