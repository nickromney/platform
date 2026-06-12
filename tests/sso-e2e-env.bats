#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export BUILD_SSO_E2E_ENV="${REPO_ROOT}/kubernetes/scripts/build-sso-e2e-env.sh"
}

@test "sso e2e env resolves Backstage gate from ordered optional tfvars" {
  local stage_tfvars="${BATS_TEST_TMPDIR}/stage-900.tfvars"
  local target_tfvars="${BATS_TEST_TMPDIR}/target.tfvars"
  local missing_tfvars="${BATS_TEST_TMPDIR}/missing.tfvars"
  local operator_tfvars="${BATS_TEST_TMPDIR}/operator.tfvars"

  printf 'enable_backstage = true\n' >"${stage_tfvars}"
  printf 'enable_backstage = true\n' >"${target_tfvars}"
  printf 'enable_backstage = false\n' >"${operator_tfvars}"

  run "${BUILD_SSO_E2E_ENV}" --execute \
    --stage-tfvars "${stage_tfvars}" \
    --optional-file "${target_tfvars}" \
    --optional-file "${missing_tfvars}" \
    --optional-file "${operator_tfvars}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SSO_E2E_ENABLE_BACKSTAGE=false"* ]]
  [[ "${output}" == *"STAGE_TFVARS=${stage_tfvars}"* ]]
  [[ "${output}" == *"STAGE_TFVARS_FILES=${stage_tfvars}:${target_tfvars}:${operator_tfvars}"* ]]

  eval "${output}"
  [ "${SSO_E2E_ENABLE_BACKSTAGE}" = "false" ]
  [ "${STAGE_TFVARS}" = "${stage_tfvars}" ]
  [ "${STAGE_TFVARS_FILES}" = "${stage_tfvars}:${target_tfvars}:${operator_tfvars}" ]
}

@test "sso e2e env previews without required runtime inputs" {
  run "${BUILD_SSO_E2E_ENV}" --dry-run

  [ "${status}" -eq 0 ]
  [ "${output}" = "INFO dry-run: would build SSO E2E environment assignments" ]
}
