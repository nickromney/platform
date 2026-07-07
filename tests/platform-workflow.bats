#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-workflow.sh"
}

@test "platform workflow options exposes stable json choices" {
  run "${SCRIPT}" options --execute --output json

  [ "${status}" -eq 0 ]
  options_json="${output}"
  run jq -r '.variants | map(.id) | join(",")' <<<"${options_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "kind,lima" ]

  run jq -r '.variants[0].path, .variants[0].class, .contexts[0].id, (.source_precedence | join(">"))' <<<"${options_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'kubernetes/kind\nlocal-created-cluster\nlocal-substrate\nstage_baseline>variant_defaults>resource_profile>image_distribution>network_profile>observability_stack>identity_stack>app_set>custom_overrides' ]

  run jq -r '.status_facets | join(",")' <<<"${options_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "cluster-access,nodes,cni,ingress,gitops,apps,observability,identity,logs" ]

  run "${SCRIPT}" options --execute --output json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"id": "700"'* ]]
  [[ "${output}" == *'"id": "920"'* ]]
  [[ "${output}" == *'"sentiment"'* ]]
  [[ "${output}" == *'"subnetcalc"'* ]]
  [[ "${output}" == *'"preset_groups"'* ]]
  [[ "${output}" == *'"local-idp-16gb"'* ]]

  run jq -r '.presets[] | select(.group == "network_profile" and .id == "cilium") | .variants | join(",")' <<<"${options_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "kind,lima" ]
}

@test "platform workflow options avoids preview command setup" {
  test_bin="${BATS_TEST_TMPDIR}/bin"
  jq_log="${BATS_TEST_TMPDIR}/jq-options.log"
  real_jq="$(command -v jq)"
  mkdir -p "${test_bin}"

  cat >"${test_bin}/jq" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${jq_log}"
exec "${real_jq}" "\$@"
EOF
  chmod +x "${test_bin}/jq"

  run env PATH="${test_bin}:${PATH}" "${SCRIPT}" options --execute --output json

  [ "${status}" -eq 0 ]
  registry_lookups="$(grep -c '.variant_contract | .registry.' "${jq_log}" || true)"
  action_metadata_lookups="$(grep -c '.action_metadata' "${jq_log}" || true)"
  [ "${registry_lookups}" -eq 0 ]
  [ "${action_metadata_lookups}" -eq 0 ]
}

@test "platform workflow previews stage 920 Langfuse commands" {
  run "${SCRIPT}" preview --execute --variant kind --stage 920 --action plan --output json

  [ "${status}" -eq 0 ]
  run jq -r '.stage, .stage_metadata.label, (.contract_requirements | map(.id) | join(",")), .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'920\nlangfuse\ncluster-access,ingress,observability,identity\nmake -C kubernetes/kind 920 plan' ]
}

@test "platform workflow preview generates app override tfvars and command" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/kind-stage700-no-sentiment.tfvars"

  run "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 700 \
    --action apply \
    --app sentiment=off \
    --app subnetcalc=on \
    --tfvars-file "${tfvars_file}" \
    --auto-approve

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Variant: kind (kubernetes/kind)"* ]]
  [[ "${output}" != *"Legacy target:"* ]]
  [[ "${output}" == *"Stage: 700"* ]]
  [[ "${output}" == *"Generated tfvars: ${tfvars_file}"* ]]
  [[ "${output}" == *"# Variant: kind, stage: 700"* ]]
  [[ "${output}" == *"enable_app_repo_sentiment = false"* ]]
  [[ "${output}" == *"enable_app_repo_subnetcalc = true"* ]]
  [[ "${output}" == *"PLATFORM_TFVARS=${tfvars_file}"* ]]
  [[ "${output}" == *"make -C kubernetes/kind 700 apply AUTO_APPROVE=1"* ]]

  run cat "${tfvars_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"enable_app_repo_sentiment = false"* ]]
  [[ "${output}" == *"enable_app_repo_subnetcalc = true"* ]]
}

@test "platform workflow accepts subcommand-first invocation under nounset" {
  run bash -u "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 700 \
    --action plan \
    --app sentiment=off \
    --output json

  [ "${status}" -eq 0 ]
  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PLATFORM_TFVARS="* ]]
  [[ "${output}" == *"make -C kubernetes/kind 700 plan"* ]]
}

@test "platform workflow preview omits tfvars when no overrides are selected" {
  run "${SCRIPT}" preview --execute --variant lima --stage 500 --action plan

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Generated tfvars: none"* ]]
  [[ "${output}" == *"make -C kubernetes/lima 500 plan"* ]]
  [[ "${output}" != *"PLATFORM_TFVARS="* ]]
}

@test "platform workflow json preview is machine-readable" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/lima-stage900.tfvars"

  run "${SCRIPT}" preview --execute \
    --variant lima \
    --stage 900 \
    --action plan \
    --app sentiment=false \
    --tfvars-file "${tfvars_file}" \
    --output json

  [ "${status}" -eq 0 ]

  preview_json="${output}"
  run jq -r '.variant.id, .stage, .action, .app_overrides.sentiment, .tfvars_file' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'lima\n900\nplan\nfalse\n'"${tfvars_file}" ]

  run jq -r '.variant.path, .variant.lifecycle_mode, .stage_metadata.context, (.contract_requirements | map(.id) | join(",")), (.effective_config.source_precedence | join(">"))' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "kubernetes/lima"$'\n'"create"$'\n'"platform-stack"$'\n'"cluster-access,ingress,identity"$'\n'"stage_baseline>variant_defaults>resource_profile>image_distribution>network_profile>observability_stack>identity_stack>app_set>custom_overrides" ]
}

@test "platform workflow json preview owns operator command previews" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/kind-stage900-no-sentiment.tfvars"

  run "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 900 \
    --action apply \
    --preset image-distribution=local-cache \
    --app sentiment=off \
    --tfvars-file "${tfvars_file}" \
    --auto-approve \
    --output json

  [ "${status}" -eq 0 ]
  preview_json="${output}"

  run jq -r '.command, .command_preview.make, .command_preview.workflow_execute, .command_preview.workflow_dry_run, .command_preview.workflow_preview_json, .command_preview.readiness' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "env KIND_IMAGE_DISTRIBUTION_MODE=registry KIND_LOCAL_IMAGE_CACHE_HOST=host.docker.internal:5002 KIND_LOCAL_IMAGE_CACHE_PUSH_HOST=127.0.0.1:5002 PLATFORM_TFVARS=${tfvars_file} make -C kubernetes/kind 900 apply AUTO_APPROVE=1"$'\n'"env KIND_IMAGE_DISTRIBUTION_MODE=registry KIND_LOCAL_IMAGE_CACHE_HOST=host.docker.internal:5002 KIND_LOCAL_IMAGE_CACHE_PUSH_HOST=127.0.0.1:5002 PLATFORM_TFVARS=${tfvars_file} make -C kubernetes/kind 900 apply AUTO_APPROVE=1"$'\n'"scripts/platform-workflow.sh apply --execute --variant kind --stage 900 --action apply --preset image-distribution=local-cache --app sentiment=false --tfvars-file ${tfvars_file} --auto-approve"$'\n'"scripts/platform-workflow.sh apply --dry-run --variant kind --stage 900 --action apply --preset image-distribution=local-cache --app sentiment=false --tfvars-file ${tfvars_file} --auto-approve"$'\n'"scripts/platform-workflow.sh preview --execute --output json --variant kind --stage 900 --action apply --preset image-distribution=local-cache --app sentiment=false --tfvars-file ${tfvars_file} --auto-approve"$'\n'"make -C kubernetes/kind readiness" ]
}

@test "platform workflow memoizes variant registry contract lookups" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/kind-stage900-no-sentiment.tfvars"
  test_bin="${BATS_TEST_TMPDIR}/bin"
  jq_log="${BATS_TEST_TMPDIR}/jq.log"
  real_jq="$(command -v jq)"
  mkdir -p "${test_bin}"

  cat >"${test_bin}/jq" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${jq_log}"
exec "${real_jq}" "\$@"
EOF
  chmod +x "${test_bin}/jq"

  run env PATH="${test_bin}:${PATH}" "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 900 \
    --action apply \
    --preset image-distribution=local-cache \
    --app sentiment=off \
    --tfvars-file "${tfvars_file}" \
    --auto-approve \
    --output json

  [ "${status}" -eq 0 ]
  runtime_host_lookups="$(grep -c '.variant_contract | .registry.runtime_host' "${jq_log}" || true)"
  push_host_lookups="$(grep -c '.variant_contract | .registry.push_host' "${jq_log}" || true)"
  [ "${runtime_host_lookups}" -le 1 ]
  [ "${push_host_lookups}" -le 1 ]
}

@test "platform workflow renders preset overlays and custom overrides" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/kind-stage900-local-idp.tfvars"

  run "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 900 \
    --action plan \
    --preset resource-profile=local-idp-16gb \
    --preset image-distribution=local-cache \
    --preset app-set=no-reference-apps \
    --set worker_count=2 \
    --tfvars-file "${tfvars_file}" \
    --output json

  [ "${status}" -eq 0 ]
  preview_json="${output}"

  run jq -r '.presets.resource_profile, .presets.image_distribution, .presets.app_set, .custom_overrides[0].id, .tfvars_file' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'local-idp-16gb\nlocal-cache\nno-reference-apps\nworker_count\n'"${tfvars_file}" ]

  run jq -r '.command, .generated_tfvars, .warnings[0]' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"KIND_IMAGE_DISTRIBUTION_MODE=registry"* ]]
  [[ "${output}" == *"PLATFORM_TFVARS=${tfvars_file}"* ]]
  [[ "${output}" == *"enable_backstage = false"* ]]
  [[ "${output}" == *"enable_app_repo_subnetcalc = true"* ]]
  [[ "${output}" == *"enable_subnetcalc_apim_gateway = false"* ]]
  [[ "${output}" == *"worker_count = 2"* ]]
  [[ "${output}" == *"Changing worker_count may recreate"* ]]
}

@test "platform workflow treats Cilium as a portable network preset" {
  run "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 200 \
    --action plan \
    --preset network-profile=cilium \
    --output json

  [ "${status}" -eq 0 ]
  run jq -r '.presets.network_profile, .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'cilium\nmake -C kubernetes/kind 200 plan' ]

}

@test "platform workflow rejects invalid app toggles" {
  run "${SCRIPT}" preview --execute --app unknown=off

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Invalid --app 'unknown'"* ]]
}

@test "platform workflow rejects invalid preset combinations before command generation" {
  run "${SCRIPT}" preview --execute --variant lima --stage 900 --preset resource-profile=local-idp-16gb

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Preset resource-profile=local-idp-16gb is not available for variant lima"* ]]

  run "${SCRIPT}" preview --execute --variant kind --stage 700 --preset observability-stack=victoria

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Preset observability-stack=victoria requires stage 800 or later"* ]]

  run "${SCRIPT}" preview --execute --variant kind --stage 100 --preset network-profile=default-cni

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Invalid --preset 'network-profile=default-cni'. Unsupported value for network-profile"* ]]

  run "${SCRIPT}" preview --execute \
    --variant lima \
    --stage 700 \
    --preset resource-profile=local-idp-16gb \
    --preset observability-stack=victoria

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Preset resource-profile=local-idp-16gb is not available for variant lima"* ]]
  [[ "${output}" != *"Preset observability-stack=victoria requires stage 800 or later"* ]]
}

@test "platform workflow rejects removed 950-local-idp stage" {
  run "${SCRIPT}" preview --execute \
    --variant kind \
    --stage 950-local-idp \
    --action apply \
    --auto-approve \
    --output json

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Stage '950-local-idp' has been removed; use --stage 900 --preset resource-profile=local-idp-16gb"* ]]
}

@test "platform workflow can save generated app overrides as a named profile" {
  profiles_dir="${BATS_TEST_TMPDIR}/profiles"

  run "${SCRIPT}" save-profile --execute \
    --variant kind \
    --stage 700 \
    --app sentiment=off \
    --app subnetcalc=off \
    --profile-name no-reference-apps \
    --profiles-dir "${profiles_dir}" \
    --output json

  [ "${status}" -eq 0 ]

  profile_file="${profiles_dir}/no-reference-apps.tfvars"
  run jq -r '.saved_profile.path' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${profile_file}" ]

  run cat "${profile_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"enable_app_repo_sentiment = false"* ]]
  [[ "${output}" == *"enable_app_repo_subnetcalc = false"* ]]
}

@test "platform workflow supports read-only helper actions without forcing a stage" {
  run "${SCRIPT}" preview --execute --variant kind --action readiness --output json

  [ "${status}" -eq 0 ]
  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "make -C kubernetes/kind readiness" ]

  run "${SCRIPT}" preview --execute --variant lima --stage 900 --action check-health --output json
  [ "${status}" -eq 0 ]
  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "make -C kubernetes/lima 900 check-health" ]
}

@test "platform workflow previews readiness commands for every variant contract" {
  local variant
  local preview_json
  local expected_command

  for variant in kind lima; do
    expected_command="$(jq -r '.readiness.command' "${REPO_ROOT}/kubernetes/variants/${variant}/variant.json")"

    run "${SCRIPT}" preview --execute --variant "${variant}" --action readiness --output json
    [ "${status}" -eq 0 ]
    preview_json="${output}"

    run jq -r '.command, .command_preview.readiness' <<<"${preview_json}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${expected_command}"$'\n'"${expected_command}" ]

    run make -C "${REPO_ROOT}/kubernetes/${variant}" -n readiness
    [ "${status}" -eq 0 ]
  done
}

@test "platform workflow ignores auto approve for read-only helpers" {
  for action in readiness status show-urls check-health check-security check-rbac; do
    run "${SCRIPT}" preview --execute --variant kind --stage 900 --action "${action}" --auto-approve --output json
    [ "${status}" -eq 0 ]
    run jq -r '.command' <<<"${output}"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"AUTO_APPROVE=1"* ]]
  done
}

@test "platform workflow supports reset without forcing a stage argument" {
  run "${SCRIPT}" preview --execute --variant kind --stage 100 --action reset --auto-approve --output json

  [ "${status}" -eq 0 ]

  run jq -r '.action, .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'reset\nmake -C kubernetes/kind reset AUTO_APPROVE=1' ]
}

@test "platform workflow supports state-reset without forcing a stage argument" {
  run "${SCRIPT}" preview --execute --variant kind --stage 700 --action state-reset --auto-approve --output json

  [ "${status}" -eq 0 ]

  run jq -r '.action, .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'state-reset\nmake -C kubernetes/kind state-reset AUTO_APPROVE=1' ]
}

@test "platform workflow refuses to run commands when a variant state lock is present" {
  lock_file="${REPO_ROOT}/terraform/.run/kubernetes/.terraform.tfstate.lock.info"
  mkdir -p "$(dirname "${lock_file}")"
  cat >"${lock_file}" <<'EOF'
{"Operation":"OperationTypePlan","Who":"tester","Created":"2026-05-02T10:21:33Z"}
EOF

  run "${SCRIPT}" apply --execute --variant kind --stage 800 --action plan

  rm -f "${lock_file}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Terraform/OpenTofu state lock present: ${lock_file}"* ]]
  [[ "${output}" == *"Lock: OperationTypePlan; tester; 2026-05-02T10:21:33Z"* ]]
  [[ "${output}" == *"Refusing to run plan while the previous Terraform/OpenTofu operation may still be active."* ]]
  [[ "${output}" == *"make -C kubernetes/kind state-reset AUTO_APPROVE=1"* ]]
}

@test "platform workflow allows state-reset when a variant state lock is present" {
  lock_file="${REPO_ROOT}/terraform/.run/kubernetes/.terraform.tfstate.lock.info"
  mkdir -p "$(dirname "${lock_file}")"
  printf '{"Operation":"OperationTypePlan"}\n' >"${lock_file}"

  run "${SCRIPT}" preview --execute --variant kind --stage 800 --action state-reset --auto-approve --output json

  rm -f "${lock_file}"

  [ "${status}" -eq 0 ]
  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "make -C kubernetes/kind state-reset AUTO_APPROVE=1" ]
}

@test "platform workflow rejects removed 950-local-idp stage for every variant" {
  run "${SCRIPT}" preview --execute --variant lima --stage 950-local-idp

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Stage '950-local-idp' has been removed; use --stage 900 --preset resource-profile=local-idp-16gb"* ]]
}
