#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-workflow.sh"
}

assert_preview() {
  local name="$1"
  local variant="$2"
  local stage="$3"
  local action="$4"
  local profile="$5"
  local sentiment="$6"
  local subnetcalc="$7"
  local expected_command="$8"
  local expected_sentiment="$9"
  local expected_subnetcalc="${10}"
  local expected_profile="${11}"
  local tfvars_file="${BATS_TEST_TMPDIR}/${name}.tfvars"
  local args=(
    preview --execute --output json
    --variant "${variant}"
    --stage "${stage}"
    --action "${action}"
    --tfvars-file "${tfvars_file}"
  )

  [ -z "${profile}" ] || return 2
  if [ -n "${sentiment}" ]; then
    args+=(--app "sentiment=${sentiment}")
  fi
  if [ -n "${subnetcalc}" ]; then
    args+=(--app "subnetcalc=${subnetcalc}")
  fi
  if [ "${action}" = "apply" ]; then
    args+=(--auto-approve)
  fi

  run "${SCRIPT}" "${args[@]}"

  [ "${status}" -eq 0 ]
  local preview_json="${output}"

  run jq -r '.command' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${expected_command}" ]

  run jq -r '.app_overrides.sentiment, .app_overrides.subnetcalc, .profile.name // "none"' <<<"${preview_json}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${expected_sentiment}"$'\n'"${expected_subnetcalc}"$'\n'"${expected_profile}" ]
}

@test "platform workflow matrix covers variant, stage, and app toggle combinations" {
  assert_preview \
    kind_100_default \
    kind 100 plan "" "" "" \
    "make -C kubernetes/kind 100 plan" \
    null null none

  assert_preview \
    kind_200_default \
    kind 200 plan "" "" "" \
    "make -C kubernetes/kind 200 plan" \
    null null none

  assert_preview \
    kind_300_default \
    kind 300 plan "" "" "" \
    "make -C kubernetes/kind 300 plan" \
    null null none

  assert_preview \
    kind_400_default \
    kind 400 plan "" "" "" \
    "make -C kubernetes/kind 400 plan" \
    null null none

  assert_preview \
    kind_500_default \
    kind 500 plan "" "" "" \
    "make -C kubernetes/kind 500 plan" \
    null null none

  assert_preview \
    kind_600_default \
    kind 600 plan "" "" "" \
    "make -C kubernetes/kind 600 plan" \
    null null none

  assert_preview \
    kind_700_default \
    kind 700 plan "" "" "" \
    "make -C kubernetes/kind 700 plan" \
    null null none

  assert_preview \
    kind_800_default \
    kind 800 plan "" "" "" \
    "make -C kubernetes/kind 800 plan" \
    null null none

  assert_preview \
    kind_900_default \
    kind 900 plan "" "" "" \
    "make -C kubernetes/kind 900 plan" \
    null null none

  assert_preview \
    kind_900_no_sentiment_apply \
    kind 900 apply "" off "" \
    "env PLATFORM_TFVARS=${BATS_TEST_TMPDIR}/kind_900_no_sentiment_apply.tfvars make -C kubernetes/kind 900 apply AUTO_APPROVE=1" \
    false null none

  assert_preview \
    kind_900_no_reference_apps_apply \
    kind 900 apply "" off off \
    "env PLATFORM_TFVARS=${BATS_TEST_TMPDIR}/kind_900_no_reference_apps_apply.tfvars make -C kubernetes/kind 900 apply AUTO_APPROVE=1" \
    false false none

  assert_preview \
    lima_700_default_plan \
    lima 700 plan "" "" "" \
    "make -C kubernetes/lima 700 plan" \
    null null none

  assert_preview \
    lima_900_no_reference_apps_plan \
    lima 900 plan "" off off \
    "env PLATFORM_TFVARS=${BATS_TEST_TMPDIR}/lima_900_no_reference_apps_plan.tfvars make -C kubernetes/lima 900 plan" \
    false false none

  assert_preview \
    slicer_700_subnetcalc_only_plan \
    slicer 700 plan "" off on \
    "env PLATFORM_TFVARS=${BATS_TEST_TMPDIR}/slicer_700_subnetcalc_only_plan.tfvars make -C kubernetes/slicer 700 plan" \
    false true none

  assert_preview \
    slicer_900_default_plan \
    slicer 900 plan "" "" "" \
    "make -C kubernetes/slicer 900 plan" \
    null null none
}

@test "platform workflow matrix rejects removed 950-local-idp stage" {
  run "${SCRIPT}" preview --execute --variant slicer --stage 950-local-idp --action plan

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Stage '950-local-idp' has been removed; use --stage 900 --preset resource-profile=local-idp-12gb"* ]]
}
