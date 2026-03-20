#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
}

@test "slicer help documents the stage-first workflow" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"make 900 check-security"* ]]
  [[ "${output}" == *"Docker-only hosts       -> use ../kind"* ]]
}

@test "slicer stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 apply AUTO_APPROVE=1"* ]]
  [[ "${output}" == *"make 100 check-security"* ]]
}

@test "slicer typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}

@test "slicer supports stage-first check-security syntax" {
  run make -n -C "${REPO_ROOT}/kubernetes/slicer" 900 check-security

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "slicer stage 900 apply wires k3s apiserver OIDC for Headlamp" {
  run grep -Fn 'run_step "configure-k3s-apiserver-oidc" $(MAKE) -C "$(MAKEFILE_DIR)" configure-k3s-apiserver-oidc;' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer stage 900 apply waits for cluster health after k3s apiserver OIDC" {
  run grep -Fn 'run_step "check-health" $(MAKE) -C "$(MAKEFILE_DIR)" check-health STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer check-sso-e2e does not repair k3s apiserver OIDC" {
  run sed -n '/^check-sso-e2e:/,/^\\.PHONY:/p' "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"configure-k3s-apiserver-oidc"* ]]
}

@test "slicer stage 100 plan explains the daemon requirement" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" 100 plan

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"require a reachable Slicer daemon"* ]]
}

@test "slicer reset prepares invalid kubeconfigs for cleanup instead of blindly backing them up" {
  run grep -Fn 'KUBECONFIG_RESET_AUTO_APPROVE="$(AUTO_APPROVE)" "$(KUBECONFIG_HELPER)" prepare-for-reset' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer reset documents local slicer-mac disk cleanup instead of VM recycle" {
  run grep -Fn 'Stop slicer-mac and remove on-device disk images for $(SLICER_VM_NAME)' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer reset warns when Docker proxy cleanup cannot be verified" {
  run grep -Fn 'existing Slicer proxy containers, if any, could not be removed' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}
