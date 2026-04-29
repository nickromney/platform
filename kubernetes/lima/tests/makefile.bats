#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "lima help documents the stage-first workflow" {
  run make -C "${REPO_ROOT}/kubernetes/lima" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"100 - cluster available"* ]]
  [[ "${output}" == *"700 - app repos"* ]]
  [[ "${output}" == *"800 - observability"* ]]
  [[ "${output}" == *"900 - sso"* ]]
  [[ "${output}" == *"make 900 check-security"* ]]
  [[ "${output}" == *"make exercise-k3s-oidc-recovery [OIDC_RECOVERY_FORMAT=text|json] [OIDC_RECOVERY_FORCE_MODE=k3s-restart]"* ]]
  [[ "${output}" == *"make start"* ]]
  [[ "${output}" == *"make merge-default-kubeconfig"* ]]
  [[ "${output}" == *"split by default"* ]]
  [[ "${output}" == *"~/.kube/limavm-k3s.yaml"* ]]
  [[ "${output}" == *"OIDC_RECOVERY_FORMAT=text|json"* ]]
  [[ "${output}" == *"<repo>/.run/profiles"* ]]
  [[ "${output}" != *"${HOME}"* ]]
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
  [[ "${output}" == *'check-security.sh" --execute '* ]]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "lima check-health forwards explicit read-only mode flags" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-health STAGE=900

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-cluster-health.sh" --execute '* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-health STAGE=900 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-cluster-health.sh" --dry-run '* ]]
}

@test "lima test-idempotence supports dry-run without touching the cluster" {
  run make -C "${REPO_ROOT}/kubernetes/lima" test-idempotence STAGE=100 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would run apply/apply/plan idempotence checks for stack 'lima'"* ]]
  [[ "${output}" == *"stage 100"* ]]
}

@test "lima check-health forwards PLATFORM_BASE_TFVARS before PLATFORM_TFVARS" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-health STAGE=900 \
    PLATFORM_BASE_TFVARS="${BATS_TEST_TMPDIR}/base.tfvars" \
    PLATFORM_TFVARS="${BATS_TEST_TMPDIR}/override.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_BASE_TFVARS:-}" --optional-file "${PLATFORM_TFVARS:-}"'* ]]
}

@test "lima rejects invalid explicit STAGE values for read-only checks with usage exit code" {
  run make -C "${REPO_ROOT}/kubernetes/lima" check-health STAGE=950

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown STAGE=950. Expected one of: 100 200 300 400 500 600 700 800 900"* ]]
}

@test "lima check-app forwards ordered tfvars through the shared builder" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" check-app STAGE=900 APP=signoz \
    PLATFORM_BASE_TFVARS="${BATS_TEST_TMPDIR}/base.tfvars" \
    PLATFORM_TFVARS="${BATS_TEST_TMPDIR}/override.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_BASE_TFVARS:-}" --optional-file "${PLATFORM_TFVARS:-}"'* ]]
  [[ "${output}" == *'check-app.sh" --execute $vf --app "${APP}"'* ]]
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

@test "lima stage 900 apply does not run browser SSO E2E verification inline" {
  run grep -Fn 'run_step "check-sso-e2e" $(MAKE) -C "$(MAKEFILE_DIR)" check-sso-e2e STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -ne 0 ]
}

@test "lima cluster-dependent read-only targets gate on assert-lima-active" {
  for target in check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e show-urls gitea-sync; do
    run sed -n "/^${target}:/,/^\\.PHONY:/p" "${REPO_ROOT}/kubernetes/lima/Makefile"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'$(MAKE) assert-lima-active >/dev/null'* ]]
  done
}

@test "lima check-version runs the active-variant assertion directly so it can report readiness" {
  run sed -n '/^check-version:/,/^\.PHONY:/p' "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"$(ASSERT_VARIANT_ACTIVE)" $(READONLY_MODE_FLAG)'* ]]
  [[ "${output}" != *'$(MAKE) assert-lima-active >/dev/null'* ]]
}

@test "lima check-sso-e2e does not repair k3s apiserver OIDC" {
  run sed -n '/^check-sso-e2e:/,/^\\.PHONY:/p' "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"configure-k3s-apiserver-oidc"* ]]
}

@test "lima exercise-k3s-oidc-recovery runs the dedicated harness with format and force knobs" {
  run make -n -C "${REPO_ROOT}/kubernetes/lima" exercise-k3s-oidc-recovery \
    OIDC_RECOVERY_FORMAT=json \
    OIDC_RECOVERY_FORCE_MODE=k3s-restart

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-kubeconfig >/dev/null'* ]]
  [[ "${output}" == *'assert-lima-active >/dev/null'* ]]
  [[ "${output}" == *'OIDC_RECOVERY_FORMAT="json"'* ]]
  [[ "${output}" == *'OIDC_RECOVERY_FORCE_MODE="k3s-restart"'* ]]
  [[ "${output}" == *'exercise-k3s-oidc-recovery.sh" --execute'* ]]
}

@test "lima reset prepares invalid kubeconfigs for cleanup instead of blindly backing them up" {
  run grep -Fn '"$(RESET_KUBECONFIG_CONTEXT)" --execute --kubeconfig "$(KUBECONFIG_PATH)"' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}

@test "lima target profile namespaces shared terraform runtime artifacts" {
  run grep -En 'runtime_artifact_scope += "lima"' \
    "${REPO_ROOT}/kubernetes/lima/targets/lima.tfvars"

  [ "${status}" -eq 0 ]
}

@test "lima reset cleans only the lima runtime artifact scope" {
  run grep -Fn 'rm -rf "$(STACK_RUNTIME_DIR)" 2>/dev/null || true; \' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'rm -rf "$(STACK_DIR)/.run" 2>/dev/null || true; \' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -ne 0 ]
}

@test "stop-lima reports the shared host ports it is releasing" {
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  list)
    if [[ "${2:-}" == "-q" ]]; then
      printf 'k3s-node-1\n'
    else
      printf 'k3s-node-1 Running 127.0.0.1:60022\n'
    fi
    ;;
  stop)
    exit 0
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/limactl"

  cat >"${TEST_BIN}/host-gateway-proxy.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/host-gateway-proxy.sh"

  run make -C "${REPO_ROOT}/kubernetes/lima" stop-lima \
    HOST_GATEWAY_PROXY="${TEST_BIN}/host-gateway-proxy.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Shared host ports managed by Lima:"* ]]
  [[ "${output}" == *"127.0.0.1:443"* ]]
  [[ "${output}" == *"127.0.0.1:30080"* ]]
  [[ "${output}" == *"127.0.0.1:30022"* ]]
  [[ "${output}" == *"127.0.0.1:3302"* ]]
}

@test "lima plan rejects invalid explicit STAGE values with usage exit code" {
  run make -C "${REPO_ROOT}/kubernetes/lima" plan STAGE=950

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown STAGE=950. Expected one of: 100 200 300 400 500 600 700 800 900"* ]]
}

@test "lima prereqs groups tool checks and does not run shell audit" {
  run env PATH="/usr/bin:/bin" make -C "${REPO_ROOT}/kubernetes/lima" prereqs STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Tool installation verification:"* ]]
  [[ "${output}" == *"Install hints:"* ]]
  [[ "${output}" != *"Shell audit:"* ]]
}

@test "lima uses the shared terragrunt make helpers for init plan and apply" {
  run grep -Fn 'include ../../mk/k8s-terragrunt.mk' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '@$(call tg_stack_init)' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '$(call tg_stack_plan,$$plan_args)' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '$(call tg_stack_apply,$$apply_args)' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}

@test "lima prereqs keeps kyverno in the optional host tool inventory" {
  run grep -Fn -- '--optional kyverno \' \
    "${REPO_ROOT}/kubernetes/lima/Makefile"

  [ "${status}" -eq 0 ]
}

@test "lima test-shell delegates to repo shell validation and shellcheck" {
  stub_root="${BATS_TEST_TMPDIR}/repo-root"
  log_file="${BATS_TEST_TMPDIR}/lima-test-shell.log"
  mkdir -p "${stub_root}/scripts"

  cat >"${stub_root}/scripts/check-bash32-compat.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bash32 %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${stub_root}/scripts/check-bash32-compat.sh"

  cat >"${stub_root}/scripts/audit-shell-scripts.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'shell-audit %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${stub_root}/scripts/audit-shell-scripts.sh"

  cat >"${TEST_BIN}/shellcheck" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'shellcheck %s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/shellcheck"

  run make -C "${REPO_ROOT}/kubernetes/lima" test-shell REPO_ROOT="${stub_root}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'bash32 --execute'* ]]
  [[ "${output}" == *$'shell-audit --execute --path scripts/audit-shell-scripts.sh --path scripts/lib --path scripts/suggest-make-goal.sh --path kubernetes/scripts --path kubernetes/lima/scripts --path terraform/kubernetes/scripts'* ]]
  [[ "${output}" == *"shellcheck ${REPO_ROOT}/kubernetes/lima/scripts/"* ]]
  [[ "${output}" == *"../../terraform/kubernetes/scripts/check-cluster-health.sh"* ]]
  [[ "${output}" == *"../../terraform/kubernetes/scripts/check-component-version.sh"* ]]
}
