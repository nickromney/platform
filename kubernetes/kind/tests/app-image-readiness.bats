#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/wait-app-image-readiness.sh"
}

@test "app image readiness contract loads app-specific wait values" {
  contract_file="${BATS_TEST_TMPDIR}/app-image-readiness-contract.json"
  cat >"${contract_file}" <<'EOF'
{
  "app_id": "sentiment",
  "repo_name": "sentiment",
  "display_name": "Sentiment",
  "workflow_id": "build-images.yaml",
  "workflow_ref": "main",
  "failure_consequence": "Registry images will not appear until it succeeds.",
  "image_names": ["sentiment-api", "sentiment-auth-ui"],
  "policy_checks": [
    {
      "file": "apps/workloads/base/all.yaml",
      "required_images": ["sentiment-api", "sentiment-auth-ui"]
    }
  ]
}
EOF

  run bash -lc "export APP_IMAGE_READINESS_CONTRACT_FILE='${contract_file}'; source '${SCRIPT}'; load_app_image_readiness_contract; printf '%s\n' \"\$APP_REPO_NAME\" \"\$APP_DISPLAY_NAME\" \"\$APP_WORKFLOW_ID\" \"\$APP_FAILURE_CONSEQUENCE\"; app_image_names; policy_required_images_for_file 'apps/workloads/base/all.yaml'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'sentiment\nSentiment\nbuild-images.yaml\nRegistry images will not appear until it succeeds.\nsentiment-api\nsentiment-auth-ui\nsentiment-api\nsentiment-auth-ui')" ]
}

@test "Terraform wait image resources delegate to app image readiness contract helper" {
  gitops_tf="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
  locals_tf="${REPO_ROOT}/terraform/kubernetes/locals.tf"

  grep -Fq "app_image_readiness_contracts" "${locals_tf}"
  grep -Fq 'app-${local.sentiment_repo_name}-image-readiness-contract.json' "${gitops_tf}"
  grep -Fq 'app-${local.subnetcalc_repo_name}-image-readiness-contract.json' "${gitops_tf}"
  grep -Fq "wait-app-image-readiness.sh" "${gitops_tf}"
  grep -Fq "APP_IMAGE_READINESS_CONTRACT_FILE" "${gitops_tf}"

  ! grep -Fq "latest_sentiment_sha()" "${gitops_tf}"
  ! grep -Fq "latest_subnetcalc_sha()" "${gitops_tf}"
  ! grep -Fq "dispatch_sentiment_workflow()" "${gitops_tf}"
  ! grep -Fq "dispatch_subnetcalc_workflow()" "${gitops_tf}"
}
