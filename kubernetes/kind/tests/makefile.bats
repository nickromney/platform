#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "kind help documents the 900 stage ladder" {
  run make -C "${REPO_ROOT}/kubernetes/kind" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make 100 apply"* ]]
  [[ "${output}" == *"make apply 100"* ]]
  [[ "${output}" == *"100 - cluster available"* ]]
  [[ "${output}" == *"700 - app repos"* ]]
  [[ "${output}" == *"800 - observability"* ]]
  [[ "${output}" == *"900 - sso"* ]]
  [[ "${output}" == *"Linux -> Docker Engine or Docker Desktop"* ]]
  [[ "${output}" == *"make merge-default-kubeconfig"* ]]
  [[ "${output}" == *"split by default"* ]]
  [[ "${output}" == *"KIND_WORKER_COUNT=1|2|..."* ]]
  [[ "${output}" == *"KIND_IMAGE_DISTRIBUTION_MODE=load|registry|hybrid|baked"* ]]
  [[ "${output}" == *"KIND_ENABLE_BACKSTAGE=auto|on|off"* ]]
  [[ "${output}" == *"image distribution mode (default: registry)"* ]]
  [[ "${output}" == *"make status"* ]]
  [[ "${output}" == *"make idp-lite plan"* ]]
  [[ "${output}" == *"make docker-prune-estimate"* ]]
  [[ "${output}" == *"make check-version [CHECK_VERSION_FORMAT=text|json]"* ]]
  [[ "${output}" == *"make check-provider-version [CHECK_VERSION_FORMAT=text|json]"* ]]
  [[ "${output}" == *"make exercise-oidc-recovery [OIDC_RECOVERY_FORMAT=text|json] [OIDC_RECOVERY_FORCE_MODE=nginx-rollout]"* ]]
  [[ "${output}" == *"CHECK_VERSION_FORMAT=text|json"* ]]
  [[ "${output}" == *"OIDC_RECOVERY_FORMAT=text|json"* ]]
  [[ "${output}" == *"~/.kube/kind-kind-local.yaml"* ]]
  [[ "${output}" == *"<repo>/.run/profiles"* ]]
  [[ "${output}" != *"${HOME}"* ]]
}

@test "kind idp-lite plan dispatches to stage 900 with the lite profile" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" idp-lite plan

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'make plan STAGE="900"'* ]]
  [[ "${output}" == *'KIND_PROFILE_TFVARS="'*"kubernetes/kind/profiles/idp-lite.tfvars"* ]]
}

@test "kind idp-lite profile keeps IDP essentials and disables heavy optional components" {
  profile="${REPO_ROOT}/kubernetes/kind/profiles/idp-lite.tfvars"

  run test -f "${profile}"
  [ "${status}" -eq 0 ]

  run grep -E '^(enable_gateway_tls|enable_gitea|enable_argocd|enable_sso)[[:space:]]*=[[:space:]]*true$' "${profile}"
  [ "${status}" -eq 0 ]

  run grep -E '^(enable_loki|enable_tempo|enable_signoz|enable_victoria_logs|enable_prometheus|enable_grafana|enable_actions_runner|enable_app_repo_subnetcalc)[[:space:]]*=[[:space:]]*false$' "${profile}"
  [ "${status}" -eq 0 ]

  run grep -E '^(enable_app_repo_sentiment|prefer_external_workload_images|prefer_external_platform_images)[[:space:]]*=[[:space:]]*true$' "${profile}"
  [ "${status}" -eq 0 ]

  run grep -E '"idp-core"|backstage|sentiment-api|sentiment-auth-ui' "${profile}"
  [ "${status}" -eq 0 ]
}

@test "kind run_step helper preserves shell arguments instead of invoking macOS apply" {
  run grep -Fn '"$${@}"' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind stage without action shows guidance" {
  run make -C "${REPO_ROOT}/kubernetes/kind" 100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Stage 100 requires an action."* ]]
  [[ "${output}" == *"make 100 apply AUTO_APPROVE=1"* ]]
  [[ "${output}" == *"make 100 check-security"* ]]
}

@test "kind typo suggests the closest workflow action" {
  run make -C "${REPO_ROOT}/kubernetes/kind" 100 aplly

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Did you mean 'apply'?"* ]]
}

@test "kind apply with a missing env file fails cleanly instead of treating it as a make goal" {
  missing_env="${BATS_TEST_TMPDIR}/missing.env"

  run env PLATFORM_ENV_FILE="${missing_env}" make -C "${REPO_ROOT}/kubernetes/kind" 100 apply

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing platform env file: ${missing_env}"* ]]
  [[ "${output}" != *"Unknown make goal '${missing_env}'"* ]]
}

@test "kind supports stage-first check-security syntax" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" 900 check-security

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"check-security.sh"* ]]
}

@test "kind keeps the target-prefixed positional workflow syntax" {
  run sed -n '/^kind:/,/^\\.PHONY:/p' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'$(MAKE) $(KIND_DISPATCH_TARGET) STAGE="$(STAGE)" AUTO_APPROVE="$(AUTO_APPROVE)"'* || "${output}" == *'make $(KIND_DISPATCH_TARGET) STAGE="$(STAGE)" AUTO_APPROVE="$(AUTO_APPROVE)"'* ]]
}

@test "kind check-health forwards PLATFORM_TFVARS to the health script" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-health STAGE=900 \
    PLATFORM_TFVARS="${BATS_TEST_TMPDIR}/override.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_TFVARS:-}"'* ]]
  [[ "${output}" == *'check-cluster-health.sh" --execute $vf'* ]]
}

@test "kind check-health forwards explicit read-only mode flags" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-health STAGE=900

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-cluster-health.sh" --execute '* ]]

  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-health STAGE=900 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'check-cluster-health.sh" --dry-run '* ]]
}

@test "kind test-idempotence supports dry-run without touching the cluster" {
  run make -C "${REPO_ROOT}/kubernetes/kind" test-idempotence STAGE=100 DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would run apply/apply/plan idempotence checks for stack 'kind'"* ]]
  [[ "${output}" == *"stage 100"* ]]
}

@test "kind check-health forwards PLATFORM_BASE_TFVARS before PLATFORM_TFVARS" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-health STAGE=900 \
    PLATFORM_BASE_TFVARS="${BATS_TEST_TMPDIR}/base.tfvars" \
    PLATFORM_TFVARS="${BATS_TEST_TMPDIR}/override.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_BASE_TFVARS:-}" --optional-file "${PLATFORM_TFVARS:-}"'* ]]
}

@test "kind rejects invalid explicit STAGE values for read-only checks with usage exit code" {
  run make -C "${REPO_ROOT}/kubernetes/kind" check-health STAGE=950

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown STAGE=950. Expected one of: 100 200 300 400 500 600 700 800 900"* ]]
}

@test "check-cluster-health accepts repeated --var-file flags in dry-run mode" {
  override_tfvars="${BATS_TEST_TMPDIR}/override.tfvars"
  missing_env="${BATS_TEST_TMPDIR}/missing.env"
  : >"${override_tfvars}"

  run env PATH="/usr/bin:/bin" PLATFORM_ENV_FILE="${missing_env}" \
    "${REPO_ROOT}/terraform/kubernetes/scripts/check-cluster-health.sh" \
    --dry-run \
    --show-urls \
    --var-file "${override_tfvars}" \
    --var-file "${REPO_ROOT}/kubernetes/kind/targets/kind.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would run stack-aware cluster health diagnostics"* ]]
}

@test "kind check-security forwards PLATFORM_TFVARS to the security script" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" 900 check-security PLATFORM_TFVARS="${BATS_TEST_TMPDIR}/override.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_TFVARS:-}"'* ]]
  [[ "${output}" == *'check-security.sh" --execute '* ]]
  [[ "${output}" == *'check-security.sh" --execute $vf'* ]]
}

@test "kind check-app forwards ordered tfvars through the shared builder" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" check-app STAGE=900 APP=signoz \
    PLATFORM_BASE_TFVARS="${BATS_TEST_TMPDIR}/base.tfvars" \
    PLATFORM_TFVARS="${BATS_TEST_TMPDIR}/override.tfvars"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'build-tfvar-args.sh" --execute --format repeated --flag --var-file '* ]]
  [[ "${output}" == *'--optional-file "${PLATFORM_BASE_TFVARS:-}" --optional-file "${PLATFORM_TFVARS:-}"'* ]]
  [[ "${output}" == *'operator-overrides.tfvars"'* ]]
  [[ "${output}" == *'check-app.sh" --execute $vf --app "${APP}"'* ]]
}

@test "kind plan rejects invalid explicit STAGE values with usage exit code" {
  run make -C "${REPO_ROOT}/kubernetes/kind" plan STAGE=950

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown STAGE=950. Expected one of: 100 200 300 400 500 600 700 800 900"* ]]
}

@test "kind apply refreshes kubeconfig after a successful apply" {
  run grep -Fn '"$(REFRESH_KIND_KUBECONFIG)" --execute; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind stage 900 apply waits for cluster health before browser SSO E2E verification" {
  run grep -Fn 'run_step "check-health" $(MAKE) -C "$(MAKEFILE_DIR)" check-health STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind gateway stages verify HTTPS entrypoints after cluster health" {
  run grep -Fn 'run_step "check-gateway-urls" $(MAKE) -C "$(MAKEFILE_DIR)" check-gateway-urls STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind check-gateway-urls uses the split kind kubeconfig" {
  run grep -Fn 'KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-gateway-urls.sh" $(READONLY_MODE_FLAG) $$vf' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind stage 900 apply runs browser SSO E2E verification after a successful apply" {
  run grep -Fn 'run_step "check-sso-e2e" $(MAKE) -C "$(MAKEFILE_DIR)" check-sso-e2e STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind check-sso-e2e forwards the rendered Backstage gate to Playwright" {
  run grep -Fn 'SSO_E2E_ENABLE_BACKSTAGE="$$enable_backstage" STAGE_TFVARS="$$stage_tfvars"' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind apply rolls Backstage after rebuilding local platform images" {
  run grep -Fn 'run_step "rollout-restart-backstage" env KUBECONFIG="$(KUBECONFIG_PATH)" kubectl --context "$(KUBECONFIG_CONTEXT)" -n idp rollout restart deployment/backstage' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"
  [ "${status}" -eq 0 ]

  run grep -Fn 'run_step "rollout-status-backstage" env KUBECONFIG="$(KUBECONFIG_PATH)" kubectl --context "$(KUBECONFIG_CONTEXT)" -n idp rollout status deployment/backstage --timeout=600s' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"
  [ "${status}" -eq 0 ]
}

@test "Backstage platform service template includes Gateway API ingress starter manifests" {
  template_root="${REPO_ROOT}/apps/backstage/catalog/templates/platform-service/content"

  run grep -Fn '../routing/httproutes.yaml' "${template_root}/kubernetes/base/kustomization.yaml"
  [ "${status}" -eq 0 ]

  run grep -Fn 'kind: HTTPRoute' "${template_root}/kubernetes/routing/httproutes.yaml"
  [ "${status}" -eq 0 ]

  run grep -Fn 'namespace: gateway-routes' "${template_root}/kubernetes/routing/httproutes.yaml"
  [ "${status}" -eq 0 ]

  run grep -Fn '${{ values.name }}.${{ environment }}.127.0.0.1.sslip.io' "${template_root}/kubernetes/routing/httproutes.yaml"
  [ "${status}" -eq 0 ]

  run grep -Fn 'kind: ReferenceGrant' "${template_root}/kubernetes/routing/httproutes.yaml"
  [ "${status}" -eq 0 ]
}

@test "Backstage platform service template permits platform gateway ingress to the frontend" {
  policy="${REPO_ROOT}/apps/backstage/catalog/templates/platform-service/content/kubernetes/policies/cilium-frontend-backend.yaml"

  run grep -Fn 'k8s:io.kubernetes.pod.namespace: platform-gateway' "${policy}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'k8s:app.kubernetes.io/name: platform-gateway-nginx' "${policy}"
  [ "${status}" -eq 0 ]
}

@test "Backstage demo app catalog entries are owned by the apps" {
  subnetcalc_catalog="${REPO_ROOT}/apps/subnetcalc/catalog-info.yaml"
  sentiment_catalog="${REPO_ROOT}/apps/sentiment/catalog-info.yaml"
  dev_config="${REPO_ROOT}/apps/backstage/app-config.yaml"
  prod_config="${REPO_ROOT}/apps/backstage/app-config.production.yaml"
  image_build="${REPO_ROOT}/kubernetes/kind/scripts/build-local-platform-images.sh"

  run grep -Fn 'backstage.io/techdocs-ref: dir:.' "${subnetcalc_catalog}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'kind: API' "${subnetcalc_catalog}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'components:' "${subnetcalc_catalog}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'backstage.io/techdocs-ref: dir:.' "${sentiment_catalog}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'kind: API' "${sentiment_catalog}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'components:' "${sentiment_catalog}"
  [ "${status}" -eq 0 ]

  run grep -Fn '../../../subnetcalc/catalog-info.yaml' "${dev_config}"
  [ "${status}" -eq 0 ]

  run grep -Fn './catalog/apps/subnetcalc/catalog-info.yaml' "${prod_config}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'copy_backstage_app_catalog "${context_dir}" "subnetcalc"' "${image_build}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'copy_backstage_app_catalog "${context_dir}" "sentiment"' "${image_build}"
  [ "${status}" -eq 0 ]
}

@test "version checks cover Backstage catalog and generated platform API pins" {
  root_check="${REPO_ROOT}/scripts/check-version.sh"
  stack_check="${REPO_ROOT}/terraform/kubernetes/scripts/check-version.sh"

  run grep -Fn 'check_backstage_catalog_pins' "${root_check}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'openapi: 3.0.3' "${root_check}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'apps/backstage/catalog/templates" -path' "${root_check}"
  [ "${status}" -eq 0 ]

  run grep -Fn "uses floating ref" "${root_check}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'check_platform_manifest_api_version_pins' "${stack_check}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'gateway.networking.k8s.io/v1' "${stack_check}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'cilium.io/v2' "${stack_check}"
  [ "${status}" -eq 0 ]
}

@test "Backstage platform service template SHA-pins checkout action" {
  workflow="${REPO_ROOT}/apps/backstage/catalog/templates/platform-service/content/.gitea/workflows/build.yaml"

  run grep -Fn 'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2' "${workflow}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'persist-credentials: false' "${workflow}"
  [ "${status}" -eq 0 ]

  run grep -Fn 'contents: read' "${workflow}"
  [ "${status}" -eq 0 ]
}

@test "kind stage 900 apply runs browser SSO E2E inside the devcontainer" {
  run grep -Fn 'run_step "check-sso-e2e" $(MAKE) -C "$(MAKEFILE_DIR)" check-sso-e2e STAGE="$(STAGE)";' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind check-sso-e2e no longer has a devcontainer carveout" {
  run grep -Fn 'ALLOW_DEVCONTAINER_BROWSER_E2E' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -ne 0 ]
}

@test "kind check-kubeconfig refreshes the split kind kubeconfig first" {
  run grep -Fn '$(MAKE) ensure-kind-kubeconfig >/dev/null; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind cluster-dependent read-only targets gate on assert-kind-active" {
  for target in check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e show-urls gitea-sync; do
    run sed -n "/^${target}:/,/^\\.PHONY:/p" "${REPO_ROOT}/kubernetes/kind/Makefile"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *'$(MAKE) assert-kind-active >/dev/null'* ]]
  done
}

@test "kind gitea-sync uses the runtime-scoped policies deploy key" {
  run sed -n '/^gitea-sync:/,/^\\.PHONY:/p' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'SSH_PRIVATE_KEY_PATH="$${SSH_PRIVATE_KEY_PATH:-$(STACK_RUNTIME_DIR)/policies-repo.id_ed25519}"'* ]]
}

@test "kind check-version runs the active-variant assertion directly so it can report readiness" {
  run sed -n '/^check-version:/,/^\.PHONY:/p' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"$(ASSERT_VARIANT_ACTIVE)" $(READONLY_MODE_FLAG)'* ]]
  [[ "${output}" != *'$(MAKE) assert-kind-active >/dev/null'* ]]
}

@test "kind exercise-oidc-recovery runs the explicit harness with format and force knobs" {
  run make -n -C "${REPO_ROOT}/kubernetes/kind" exercise-oidc-recovery \
    OIDC_RECOVERY_FORMAT=json \
    OIDC_RECOVERY_FORCE_MODE=nginx-rollout

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'ensure-kind-kubeconfig >/dev/null'* ]]
  [[ "${output}" == *'assert-kind-active >/dev/null'* ]]
  [[ "${output}" == *'OIDC_RECOVERY_FORMAT="json"'* ]]
  [[ "${output}" == *'OIDC_RECOVERY_FORCE_MODE="nginx-rollout"'* ]]
  [[ "${output}" == *'exercise-kind-oidc-recovery.sh" --execute'* ]]
}

@test "kind exports the absolute stack and config paths into Terraform" {
  run grep -Fn 'export TF_VAR_kind_stack_dir := $(abspath $(STACK_DIR))' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'export TF_VAR_kind_config_path := $(abspath $(STACK_DIR))/kind-config.yaml' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind uses the shared terragrunt make helpers for init plan and apply" {
  run grep -Fn 'include ../../mk/k8s-terragrunt.mk' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '@$(call tg_stack_init)' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '$(call tg_stack_plan,$$plan_args)' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '$(call tg_stack_apply,$$apply_args)' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "terragrunt reads the kind stack and config paths from the exported env vars" {
  run grep -Fn 'kind_stack_dir        = get_env("TF_VAR_kind_stack_dir", get_original_terragrunt_dir())' \
    "${REPO_ROOT}/terraform/kubernetes/terragrunt.hcl"

  [ "${status}" -eq 0 ]

  run grep -Fn 'kind_config_path      = get_env("TF_VAR_kind_config_path", "${get_original_terragrunt_dir()}/kind-config.yaml")' \
    "${REPO_ROOT}/terraform/kubernetes/terragrunt.hcl"

  [ "${status}" -eq 0 ]
}

@test "kind stage tfvars no longer hardcode a cache-relative kind config path" {
  run grep -REn 'kind_config_path[[:space:]]*=[[:space:]]*"./kind-config.yaml"' \
    "${REPO_ROOT}/kubernetes/kind/stages"

  [ "${status}" -ne 0 ]
}

@test "kind prereqs surfaces Docker registry auth status" {
  run grep -Fn 'echo "Docker registry auth:"; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn '"$(CHECK_DOCKER_REGISTRY_AUTH)" --execute dhi.io "Docker Hardened Images (dhi.io)" || true; \' "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind prereqs groups tool checks and does not run shell audit" {
  run env PATH="/usr/bin:/bin" make -C "${REPO_ROOT}/kubernetes/kind" prereqs STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Tool installation verification:"* ]]
  [[ "${output}" == *"Install hints:"* ]]
  [[ "${output}" != *"Shell audit:"* ]]
}

@test "kind prereqs keeps kyverno in the optional host tool inventory" {
  run grep -Fn -- '--optional kyverno \' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind check-version can emit a combined machine-readable JSON report" {
  stub_stack="${BATS_TEST_TMPDIR}/stack"
  stub_scripts="${stub_stack}/scripts"
  kubeconfig_path="${BATS_TEST_TMPDIR}/kind-kind-local.yaml"
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  mkdir -p "${stub_scripts}"
  : >"${kubeconfig_path}"

  cat >"${stub_scripts}/check-version.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"report":"components"}'
EOF
  chmod +x "${stub_scripts}/check-version.sh"

  cat >"${stub_scripts}/check-provider-version.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"report":"providers"}'
EOF
  chmod +x "${stub_scripts}/check-provider-version.sh"

  cat >"${TEST_BIN}/ensure-kind-kubeconfig.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ensure-kind-kubeconfig.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/kind","variants":{"kind":{"path":"kubernetes/kind","state":"running"},"lima":{"path":"kubernetes/lima","state":"absent"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${status_stub}"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run make -C "${REPO_ROOT}/kubernetes/kind" check-version \
    STACK_DIR="${stub_stack}" \
    ENSURE_KIND_KUBECONFIG="${TEST_BIN}/ensure-kind-kubeconfig.sh" \
    PLATFORM_STATUS_SCRIPT="${status_stub}" \
    KUBECONFIG_PATH="${kubeconfig_path}" \
    CHECK_VERSION_FORMAT=json

  [ "${status}" -eq 0 ]

  run jq -r '.component_report.report + "|" + .provider_report.report' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "components|providers" ]
}

@test "kind check-version fails before the audit when another tracked variant owns the machine" {
  stub_stack="${BATS_TEST_TMPDIR}/stack"
  stub_scripts="${stub_stack}/scripts"
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  log_file="${BATS_TEST_TMPDIR}/check-version.log"
  kubectl_log="${BATS_TEST_TMPDIR}/kubectl.log"
  mkdir -p "${stub_scripts}"

  cat >"${stub_scripts}/check-version.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'component audit invoked\n' >>"${log_file}"
EOF
  chmod +x "${stub_scripts}/check-version.sh"

  cat >"${stub_scripts}/check-provider-version.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'provider audit invoked\n' >>"${log_file}"
EOF
  chmod +x "${stub_scripts}/check-provider-version.sh"

  cat >"${TEST_BIN}/ensure-kind-kubeconfig.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ensure-kind-kubeconfig.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/lima","variants":{"kind":{"path":"kubernetes/kind","state":"absent"},"lima":{"path":"kubernetes/lima","state":"running"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${status_stub}"

  cat >"${TEST_BIN}/kubectl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'kubectl %s\n' "\$*" >>"${kubectl_log}"
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run make -C "${REPO_ROOT}/kubernetes/kind" check-version \
    STACK_DIR="${stub_stack}" \
    ENSURE_KIND_KUBECONFIG="${TEST_BIN}/ensure-kind-kubeconfig.sh" \
    PLATFORM_STATUS_SCRIPT="${status_stub}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"currently owned by kubernetes/lima"* ]]
  [[ "${output}" == *"make -C kubernetes/lima stop-lima"* ]]
  [ ! -e "${log_file}" ]
  [ ! -e "${kubectl_log}" ]
}

@test "kind check-version positively reports that the expected cluster is active before the audit" {
  stub_stack="${BATS_TEST_TMPDIR}/stack"
  stub_scripts="${stub_stack}/scripts"
  kubeconfig_path="${BATS_TEST_TMPDIR}/kind-kind-local.yaml"
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  mkdir -p "${stub_scripts}"
  : >"${kubeconfig_path}"

  cat >"${stub_scripts}/check-version.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'component audit ok\n'
EOF
  chmod +x "${stub_scripts}/check-version.sh"

  cat >"${stub_scripts}/check-provider-version.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'provider audit ok\n'
EOF
  chmod +x "${stub_scripts}/check-provider-version.sh"

  cat >"${TEST_BIN}/ensure-kind-kubeconfig.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ensure-kind-kubeconfig.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"overall_state":"running","active_variant_path":"kubernetes/kind","variants":{"kind":{"path":"kubernetes/kind","state":"running"},"lima":{"path":"kubernetes/lima","state":"absent"},"slicer":{"path":"kubernetes/slicer","state":"absent"}}}'
EOF
  chmod +x "${status_stub}"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  run make -C "${REPO_ROOT}/kubernetes/kind" check-version \
    STACK_DIR="${stub_stack}" \
    ENSURE_KIND_KUBECONFIG="${TEST_BIN}/ensure-kind-kubeconfig.sh" \
    PLATFORM_STATUS_SCRIPT="${status_stub}" \
    KUBECONFIG_PATH="${kubeconfig_path}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubernetes/kind is the active variant on this machine"* ]]
  [[ "${output}" == *"Proceeding with checks."* ]]
  [[ "${output}" == *"Running component and chart version audit..."* ]]
  [[ "${output}" == *"component audit ok"* ]]
}

@test "kind test-shell delegates to repo shell validation and shellcheck" {
  stub_root="${BATS_TEST_TMPDIR}/repo-root"
  log_file="${BATS_TEST_TMPDIR}/kind-test-shell.log"
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

  run make -C "${REPO_ROOT}/kubernetes/kind" test-shell REPO_ROOT="${stub_root}"

  [ "${status}" -eq 0 ]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *$'bash32 --execute'* ]]
  [[ "${output}" == *$'shell-audit --execute --path scripts/audit-shell-scripts.sh --path scripts/lib --path scripts/suggest-make-goal.sh --path kubernetes/scripts --path kubernetes/kind/scripts --path terraform/kubernetes/scripts'* ]]
  [[ "${output}" == *"shellcheck ${REPO_ROOT}/kubernetes/kind/scripts/"* ]]
  [[ "${output}" == *"../../terraform/kubernetes/scripts/check-cluster-health.sh"* ]]
  [[ "${output}" == *"../../terraform/kubernetes/scripts/check-version.sh"* ]]
}

@test "kind ensure-kind-running revives a stopped cluster before terraform" {
  state_file="${BATS_TEST_TMPDIR}/docker-state"
  printf 'stopped' >"${state_file}"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state_file="${state_file}"
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  info)
    exit 0
    ;;
  ps)
    include_all=0
    while [[ \$# -gt 0 ]]; do
      case "\$1" in
        -a)
          include_all=1
          shift
          ;;
        --format)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "\${include_all}" == "1" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
      exit 0
    fi
    if [[ "\$(cat "\${state_file}")" == "running" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
    fi
    exit 0
    ;;
  start)
    printf 'running' >"\${state_file}"
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" && "${2:-}" == "clusters" ]]; then
  printf '%s\n' kind-local
  exit 0
fi
if [[ "${1:-}" == "export" && "${2:-}" == "kubeconfig" ]]; then
  kubeconfig=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --kubeconfig)
        kubeconfig="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  mkdir -p "$(dirname "${kubeconfig}")"
  cat >"${kubeconfig}" <<'YAML'
apiVersion: v1
clusters: []
contexts: []
current-context: ""
kind: Config
preferences: {}
users: []
YAML
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "${args}" == *"config get-contexts"* ]]; then
  exit 0
fi
if [[ "${args}" == *"config use-context"* ]]; then
  exit 0
fi
if [[ "${args}" == *"get --raw=/readyz"* ]]; then
  exit 0
fi
if [[ "${args}" == *"get nodes -o wide"* ]]; then
  printf '%s\n' 'NAME STATUS ROLES AGE VERSION'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  run env \
    KIND_CHECK_SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" \
    KUBECONFIG_HELPER=/bin/true \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    make -C "${REPO_ROOT}/kubernetes/kind" ensure-kind-running

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kind-local exists but is stopped; starting node containers..."* ]]
  [[ "${output}" == *"kind-local is running again."* ]]
  [[ "$(cat "${state_file}")" == "running" ]]
}

@test "kind reset prepares invalid kubeconfigs for cleanup instead of blindly backing them up" {
  run grep -Fn '"$(RESET_KUBECONFIG_CONTEXT)" --execute --kubeconfig "$$KUBECONFIG_PATH"' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind reset executes the cluster delete helper instead of previewing it" {
  run grep -Fn '"$(DELETE_KIND_CLUSTER)" --execute --name "$$CLUSTER_NAME"' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]
}

@test "kind ensure-kind-running fails before docker start when planned host ports are occupied" {
  state_file="${BATS_TEST_TMPDIR}/docker-state"
  printf 'stopped' >"${state_file}"

  cat >"${TEST_BIN}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state_file="${state_file}"
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  ps)
    include_all=0
    while [[ \$# -gt 0 ]]; do
      case "\$1" in
        -a)
          include_all=1
          shift
          ;;
        --format)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "\${include_all}" == "1" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
      exit 0
    fi
    if [[ "\$(cat "\${state_file}")" == "running" ]]; then
      printf '%s\n' kind-local-control-plane kind-local-worker
    fi
    exit 0
    ;;
  start)
    printf 'running' >"\${state_file}"
    exit 0
    ;;
esac
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" && "${2:-}" == "clusters" ]]; then
  printf '%s\n' kind-local
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:30080"* ]]; then
  cat <<'OUT'
COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
limactl 13774 nick   29u  IPv4 0xdeadbeef      0t0  TCP 127.0.0.1:30080 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/ps"

  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/limactl"

  run env \
    KIND_CHECK_SLICER_SOCKET="${BATS_TEST_TMPDIR}/missing.sock" \
    KUBECONFIG_HELPER=/bin/true \
    KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/kind-kind-local.yaml" \
    DEFAULT_KUBECONFIG_PATH="${BATS_TEST_TMPDIR}/config" \
    make -C "${REPO_ROOT}/kubernetes/kind" ensure-kind-running

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL argocd host port 127.0.0.1:30080 is already in use"* ]]
  [[ "${output}" != *"Starting kind-local node containers..."* ]]
  [[ "$(cat "${state_file}")" == "stopped" ]]
}

@test "stage monotonicity check passes for the current stage files" {
  run make -C "${REPO_ROOT}/kubernetes/kind" check-stage-monotonicity

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   stage monotonicity"* ]]
}

@test "kind host port preflight passes when no listeners are present" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  run make -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   kind host ports available:"* ]]
}

@test "kind host port preflight reports listener conflicts with overridden tfvars" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"-iTCP:4443"* ]]; then
  cat <<'OUT'
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
com.docke 27719 nick  168u  IPv6 0xdeadbeef      0t0  TCP *:4443 (LISTEN)
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  printf '%s\n' $'laemp-test-debian\t0.0.0.0:4443->443/tcp, [::]:4443->443/tcp'
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  override_file="${BATS_TEST_TMPDIR}/kind-port-overrides.tfvars"
  cat >"${override_file}" <<'EOF'
gateway_https_host_port = 4443
EOF

  run env PLATFORM_TFVARS="${override_file}" make -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL gateway-https host port 127.0.0.1:4443 is already in use"* ]]
  [[ "${output}" == *"Planned mapping: gateway_https_host_port=4443"* ]]
  [[ "${output}" == *"Conflicting Docker publishers:"* ]]
  [[ "${output}" == *"laemp-test-debian: 0.0.0.0:4443->443/tcp, [::]:4443->443/tcp"* ]]
  [[ "${output}" == *"TCP *:4443 (LISTEN)"* ]]
}

@test "kind host port preflight reports overlapping planned host ports" {
  cat >"${TEST_BIN}/lsof" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/lsof"

  override_file="${BATS_TEST_TMPDIR}/kind-port-overlap.tfvars"
  cat >"${override_file}" <<'EOF'
gateway_https_host_port = 30080
EOF

  run env PLATFORM_TFVARS="${override_file}" make -C "${REPO_ROOT}/kubernetes/kind" check-kind-host-ports STAGE=100

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL planned kind host port overlap: gateway-https (127.0.0.1:30080) conflicts with argocd (127.0.0.1:30080)"* ]]
}

@test "kind target profile namespaces shared terraform runtime artifacts" {
  run grep -En 'runtime_artifact_scope += "kind"' \
    "${REPO_ROOT}/kubernetes/kind/targets/kind.tfvars"

  [ "${status}" -eq 0 ]
}

@test "kind reset cleans only the kind runtime artifact scope" {
  run grep -Fn 'rm -rf "$(STACK_RUNTIME_DIR)" 2>/dev/null || true; \' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -eq 0 ]

  run grep -Fn 'rm -rf "$(STACK_DIR)/.run" 2>/dev/null || true; \' \
    "${REPO_ROOT}/kubernetes/kind/Makefile"

  [ "${status}" -ne 0 ]
}
