#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "slicer help documents the stage-first workflow" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"100 - cluster available"* ]]
  [[ "${output}" == *"700 - app repos"* ]]
  [[ "${output}" == *"800 - observability"* ]]
  [[ "${output}" == *"900 - sso"* ]]
  [[ "${output}" == *"make 900 check-security"* ]]
  [[ "${output}" == *"Docker-only hosts       -> use ../kind"* ]]
  [[ "${output}" == *"make merge-default-kubeconfig"* ]]
  [[ "${output}" == *"split by default"* ]]
  [[ "${output}" == *"~/.kube/slicer-k3s.yaml"* ]]
  [[ "${output}" == *"~/slicer-mac/slicer.sock"* ]]
  [[ "${output}" == *"<repo>/.run/profiles"* ]]
  [[ "${output}" == *"make state-reset  [AUTO_APPROVE=1]"* ]]
  [[ "${output}" != *"${HOME}"* ]]
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
  [[ "${output}" == *'check-security.sh" --execute '* ]]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "slicer check-health forwards explicit read-only mode flags" {
  run make -n -C "${REPO_ROOT}/kubernetes/slicer" check-health STAGE=900

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-cluster-health.sh" --execute '* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/slicer" check-health STAGE=900 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-cluster-health.sh" --dry-run '* ]]
}

@test "slicer test-idempotence supports dry-run without touching the cluster" {
  run make -C "${REPO_ROOT}/kubernetes/slicer" test-idempotence STAGE=100 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would run apply/apply/plan idempotence checks for stack 'slicer'"* ]]
  [[ "${output}" == *"stage 100"* ]]
}

@test "slicer configure-k3s-apiserver-oidc forwards explicit read-only mode flags" {
  run make -n -C "${REPO_ROOT}/kubernetes/slicer" configure-k3s-apiserver-oidc STAGE=900

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'configure-k3s-apiserver-oidc.sh" --execute'* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/slicer" configure-k3s-apiserver-oidc STAGE=900 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'configure-k3s-apiserver-oidc.sh" --dry-run'* ]]
}

@test "slicer stage 900 apply wires k3s apiserver OIDC for Headlamp" {
  run grep -Fn 'run_step "configure-k3s-apiserver-oidc" $(MAKE) -C "$(MAKEFILE_DIR)" configure-k3s-apiserver-oidc STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer stage 900 apply waits for cluster health after k3s apiserver OIDC" {
  run grep -Fn 'run_step "check-health" $(MAKE) -C "$(MAKEFILE_DIR)" check-health STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer stage 900 apply verifies gateway URLs before browser SSO E2E" {
  run grep -Fn 'run_step "check-gateway-urls" $(MAKE) -C "$(MAKEFILE_DIR)" check-gateway-urls STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer stage 900 apply runs browser SSO E2E verification after health checks" {
  run grep -Fn 'run_step "check-sso-e2e" $(MAKE) -C "$(MAKEFILE_DIR)" check-sso-e2e STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer check-sso-e2e uses the split kubeconfig and rendered Backstage gate" {
  run grep -Fn 'KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" SSO_E2E_ENABLE_BACKSTAGE="$$enable_backstage" STAGE_TFVARS="$$stage_tfvars"' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'BUILD_TFVAR_ARGS := $(K8S_SCRIPTS_DIR)/build-tfvar-args.sh' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer target profile rewrites platform-mcp to the local image cache" {
  run grep -Fn 'platform-mcp                         = "192.168.64.1:5002/platform/platform-mcp:latest"' \
    "${REPO_ROOT}/kubernetes/slicer/targets/slicer.tfvars"

  [ "${status}" -eq 0 ]
}

@test "slicer cluster-dependent read-only targets gate on assert-slicer-active" {
  for target in check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e show-urls gitea-sync; do
    run sed -n "/^${target}:/,/^\\.PHONY:/p" "${REPO_ROOT}/kubernetes/slicer/Makefile"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'$(MAKE) assert-slicer-active >/dev/null'* ]]
  done
}

@test "slicer check-version runs the active-variant assertion directly so it can report readiness" {
  run sed -n '/^check-version:/,/^\.PHONY:/p' "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"$(ASSERT_VARIANT_ACTIVE)" $(READONLY_MODE_FLAG)'* ]]
  [[ "${output}" != *'$(MAKE) assert-slicer-active >/dev/null'* ]]
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

@test "slicer stage 100 apply starts the daemon before prereqs after a reset" {
  run grep -Fn 'run_step "daemon-up" $(MAKE) daemon-up;' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'run_step "prereqs" $(MAKE) prereqs;' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer reset prepares invalid kubeconfigs for cleanup instead of blindly backing them up" {
  run grep -Fn 'KUBECONFIG_RESET_AUTO_APPROVE="$(AUTO_APPROVE)" "$(KUBECONFIG_HELPER)" --execute --action prepare-for-reset --kubeconfig' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer reset documents local slicer-mac disk cleanup instead of VM recycle" {
  run grep -Fn 'Stop slicer-mac and remove on-device disk images for $(SLICER_VM_NAME)' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer state-reset removes only the local terraform lock" {
  state_dir="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${state_dir}"
  lock_file="${state_dir}/.terraform.tfstate.lock.info"
  state_file="${state_dir}/terraform.tfstate"
  printf '{"version":4}\n' >"${state_file}"
  printf '{"Operation":"OperationTypePlan","Who":"tester","Created":"2026-05-02T10:21:33Z"}\n' >"${lock_file}"

  run make -C "${REPO_ROOT}/kubernetes/slicer" state-reset STATE_LOCK_FILE="${lock_file}" AUTO_APPROVE=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Lock: OperationTypePlan; tester; 2026-05-02T10:21:33Z"* ]]
  [[ "${output}" == *"OK   Removed Terraform/OpenTofu state lock: ${lock_file}"* ]]
  [ -f "${state_file}" ]
  [ ! -e "${lock_file}" ]
}

@test "slicer reset warns when Docker proxy cleanup cannot be verified" {
  run grep -Fn 'existing Slicer proxy containers, if any, could not be removed' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer target profile namespaces shared terraform runtime artifacts" {
  run grep -En 'runtime_artifact_scope += "slicer"' \
    "${REPO_ROOT}/kubernetes/slicer/targets/slicer.tfvars"

  [ "${status}" -eq 0 ]
}

@test "slicer reset cleans only the slicer runtime artifact scope" {
  run grep -Fn 'rm -rf "$(STACK_RUNTIME_DIR)" 2>/dev/null || true; \' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'rm -rf "$(STACK_DIR)/.run" 2>/dev/null || true; \' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -ne 0 ]
}

@test "slicer reset does not stop other platform runtimes" {
  run bash -c 'sed -n "/^reset:/,/^env:/p" "$1" | grep -E "STOP_PLATFORM_RUNTIMES|Stopping conflicting platform runtimes|Stop conflicting kind/Lima runtimes" || true' _ \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "stop-slicer reports the shared host ports it is releasing" {
  cat >"${TEST_BIN}/resolve-socket.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${BATS_TEST_TMPDIR}/missing.sock"
EOF
  chmod +x "${TEST_BIN}/resolve-socket.sh"

  cat >"${TEST_BIN}/host-gateway-proxy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/host-gateway-proxy.sh"

  cat >"${TEST_BIN}/host-forwards.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/host-forwards.sh"

  cat >"${TEST_BIN}/stop-daemon.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/stop-daemon.sh"

  run make -C "${REPO_ROOT}/kubernetes/slicer" stop-slicer \
    RESOLVE_SOCKET="${TEST_BIN}/resolve-socket.sh" \
    HOST_GATEWAY_PROXY="${TEST_BIN}/host-gateway-proxy.sh" \
    HOST_FORWARDS="${TEST_BIN}/host-forwards.sh" \
    STOP_DAEMON="${TEST_BIN}/stop-daemon.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Shared host ports managed by Slicer:"* ]]
  [[ "${output}" == *"127.0.0.1:443"* ]]
  [[ "${output}" == *"127.0.0.1:30080"* ]]
  [[ "${output}" == *"127.0.0.1:3302"* ]]
}

@test "slicer check-kubeconfig skips kubie lint noise when there are no contexts yet" {
  run sed -n '/^check-kubeconfig:/,/^\\.PHONY:/p' "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'kubie lint skipped (no kubeconfig contexts yet)'* ]]
  [[ "${output}" == *'[ "$$default_count" -eq 0 ] && [ "$$target_count" -eq 0 ]'* ]]
}

@test "slicer prereqs groups tool checks and does not run shell audit" {
  run env PATH="/usr/bin:/bin" SLICER_USE_LOCAL_MAC=0 make -C "${REPO_ROOT}/kubernetes/slicer" prereqs STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Tool installation verification:"* ]]
  [[ "${output}" == *"Install hints:"* ]]
  [[ "${output}" != *"Shell audit:"* ]]
}

@test "slicer prereqs keeps kyverno in the optional host tool inventory" {
  run grep -Fn 'optional=(bats bun cilium helm kubectx kubie kyverno mkcert node npm npx shellcheck yamllint); \' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}

@test "slicer uses the shared terragrunt make helpers for init plan and apply" {
  run grep -Fn 'include ../../mk/k8s-terragrunt.mk' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '@$(call tg_stack_init)' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '$(call tg_stack_plan,$$plan_args)' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '$(call tg_stack_apply,$$apply_args)' \
    "${REPO_ROOT}/kubernetes/slicer/Makefile"

  [ "${status}" -eq 0 ]
}
