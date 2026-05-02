#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-workflow.sh"
}

@test "platform workflow options exposes stable json choices" {
  run "${SCRIPT}" options --execute --output json

  [ "${status}" -eq 0 ]
  run jq -r '.targets | join(",")' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "kind,lima,slicer" ]

  run "${SCRIPT}" options --execute --output json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"id": "700"'* ]]
  [[ "${output}" == *'"sentiment"'* ]]
  [[ "${output}" == *'"subnetcalc"'* ]]
}

@test "platform workflow preview generates app override tfvars and command" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/kind-stage700-no-sentiment.tfvars"

  run "${SCRIPT}" preview --execute \
    --target kind \
    --stage 700 \
    --action apply \
    --app sentiment=off \
    --app subnetcalc=on \
    --tfvars-file "${tfvars_file}" \
    --auto-approve

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Target: kind (kubernetes/kind)"* ]]
  [[ "${output}" == *"Stage: 700"* ]]
  [[ "${output}" == *"Generated tfvars: ${tfvars_file}"* ]]
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
    --target kind \
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
  run "${SCRIPT}" preview --execute --target lima --stage 500 --action plan

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Generated tfvars: none"* ]]
  [[ "${output}" == *"make -C kubernetes/lima 500 plan"* ]]
  [[ "${output}" != *"PLATFORM_TFVARS="* ]]
}

@test "platform workflow json preview is machine-readable" {
  tfvars_file="${BATS_TEST_TMPDIR}/operator/slicer-stage900.tfvars"

  run "${SCRIPT}" preview --execute \
    --target slicer \
    --stage 900 \
    --action plan \
    --app sentiment=false \
    --tfvars-file "${tfvars_file}" \
    --output json

  [ "${status}" -eq 0 ]

  run jq -r '.target, .stage, .action, .app_overrides.sentiment, .tfvars_file' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'slicer\n900\nplan\nfalse\n'"${tfvars_file}" ]
}

@test "platform workflow rejects invalid app toggles" {
  run "${SCRIPT}" preview --execute --app unknown=off

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Invalid --app 'unknown'"* ]]
}

@test "platform workflow supports the kind 950-local-idp target" {
  run "${SCRIPT}" preview --execute \
    --target kind \
    --stage 950-local-idp \
    --action apply \
    --auto-approve \
    --output json

  [ "${status}" -eq 0 ]

  run jq -r '.stage, .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'950-local-idp\nmake -C kubernetes/kind 950-local-idp apply AUTO_APPROVE=1' ]
}

@test "platform workflow can save generated app overrides as a named profile" {
  profiles_dir="${BATS_TEST_TMPDIR}/profiles"

  run "${SCRIPT}" save-profile --execute \
    --target kind \
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
  run "${SCRIPT}" preview --execute --target slicer --action status --output json

  [ "${status}" -eq 0 ]

  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "make -C kubernetes/slicer status" ]

  run "${SCRIPT}" preview --execute --target lima --stage 900 --action check-health --output json
  [ "${status}" -eq 0 ]
  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "make -C kubernetes/lima 900 check-health" ]
}

@test "platform workflow supports reset without forcing a stage argument" {
  run "${SCRIPT}" preview --execute --target kind --stage 100 --action reset --auto-approve --output json

  [ "${status}" -eq 0 ]

  run jq -r '.action, .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'reset\nmake -C kubernetes/kind reset AUTO_APPROVE=1' ]
}

@test "platform workflow supports state-reset without forcing a stage argument" {
  run "${SCRIPT}" preview --execute --target kind --stage 700 --action state-reset --auto-approve --output json

  [ "${status}" -eq 0 ]

  run jq -r '.action, .command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'state-reset\nmake -C kubernetes/kind state-reset AUTO_APPROVE=1' ]
}

@test "platform workflow refuses to run commands when a target state lock is present" {
  lock_file="${REPO_ROOT}/terraform/.run/kubernetes/.terraform.tfstate.lock.info"
  mkdir -p "$(dirname "${lock_file}")"
  cat >"${lock_file}" <<'EOF'
{"Operation":"OperationTypePlan","Who":"tester","Created":"2026-05-02T10:21:33Z"}
EOF

  run "${SCRIPT}" apply --execute --target kind --stage 800 --action plan

  rm -f "${lock_file}"

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Terraform/OpenTofu state lock present: ${lock_file}"* ]]
  [[ "${output}" == *"Lock: OperationTypePlan; tester; 2026-05-02T10:21:33Z"* ]]
  [[ "${output}" == *"Refusing to run plan while the previous Terraform/OpenTofu operation may still be active."* ]]
  [[ "${output}" == *"make -C kubernetes/kind state-reset AUTO_APPROVE=1"* ]]
}

@test "platform workflow allows state-reset when a target state lock is present" {
  lock_file="${REPO_ROOT}/terraform/.run/kubernetes/.terraform.tfstate.lock.info"
  mkdir -p "$(dirname "${lock_file}")"
  printf '{"Operation":"OperationTypePlan"}\n' >"${lock_file}"

  run "${SCRIPT}" preview --execute --target kind --stage 800 --action state-reset --auto-approve --output json

  rm -f "${lock_file}"

  [ "${status}" -eq 0 ]
  run jq -r '.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "make -C kubernetes/kind state-reset AUTO_APPROVE=1" ]
}

@test "platform workflow rejects 950-local-idp for non-kind targets" {
  run "${SCRIPT}" preview --execute --target lima --stage 950-local-idp

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Stage '950-local-idp' is only available for target kind"* ]]
}
