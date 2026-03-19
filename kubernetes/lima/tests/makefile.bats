#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "lima help documents the stage-first workflow" {
  run make -C "${REPO_ROOT}/kubernetes/lima" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"make 900 check-security"* ]]
  [[ "${output}" == *"make start"* ]]
}

@test "lima run_step helper preserves shell arguments instead of invoking macOS apply" {
  run grep -Fn '"$$@"' "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}

@test "lima stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/lima" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 plan"* ]]
  [[ "${output}" == *"make 100 check-security"* ]]
}

@test "lima typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/lima" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}

@test "lima supports stage-first check-security syntax" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" 900 check-security

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "lima stage 900 apply wires k3s apiserver OIDC for Headlamp" {
  run grep -Fn 'run_step "configure-k3s-apiserver-oidc" $(MAKE) -C "$(MAKEFILE_DIR)" configure-k3s-apiserver-oidc;' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}

@test "lima stage 900 apply waits for cluster health after k3s apiserver OIDC" {
  run grep -Fn 'run_step "check-health" $(MAKE) -C "$(MAKEFILE_DIR)" check-health STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}

@test "lima check-sso-e2e does not repair k3s apiserver OIDC" {
  run sed -n '/^check-sso-e2e:/,/^\\.PHONY:/p' "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"configure-k3s-apiserver-oidc"* ]]
}

@test "lima reset prepares invalid kubeconfigs for cleanup instead of blindly backing them up" {
  run grep -Fn 'KUBECONFIG_RESET_AUTO_APPROVE="$(AUTO_APPROVE)" "$(KUBECONFIG_HELPER)" prepare-for-reset' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}
