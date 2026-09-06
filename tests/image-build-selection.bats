#!/usr/bin/env bats
setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export REPO_ROOT
}
@test "profile selection keeps Keycloak but skips disabled gateways and workload" {
  cat >"${BATS_TEST_TMPDIR}/profile.tfvars" <<'VARS'
enable_sso = true
enable_argocd = true
enable_grafana = false
enable_app_repo_sentiment = true
enable_app_repo_subnetcalc = false
enable_apim_simulator = false
enable_subnetcalc_apim_gateway = false
enable_agentgateway_ai_gateway = false
VARS
  export IMAGE_BUILD_TFVARS_FILES="${BATS_TEST_TMPDIR}/profile.tfvars"
  run bash -eu -c '
    source "$REPO_ROOT/kubernetes/workflow/image-selection-lib.sh"
    image_selection_enabled platform keycloak
    image_selection_enabled workload sentiment-api
    ! image_selection_enabled workload subnetcalc-api
    ! image_selection_enabled platform platform-mcp
    ! image_selection_enabled platform auth-chat
    ! image_selection_enabled platform grafana-victorialogs
  '
  [ "$status" -eq 0 ]
}
@test "selection applies later tfvars overrides and retains standalone defaults" {
  printf 'enable_sso = true\n' >"${BATS_TEST_TMPDIR}/base"
  printf 'enable_sso = false\n' >"${BATS_TEST_TMPDIR}/override"
  export IMAGE_BUILD_TFVARS_FILES="${BATS_TEST_TMPDIR}/base"$'\n'"${BATS_TEST_TMPDIR}/override"
  run bash -eu -c '
    source "$REPO_ROOT/kubernetes/workflow/image-selection-lib.sh"
    ! image_selection_enabled platform keycloak
    unset IMAGE_BUILD_TFVARS_FILES
    image_selection_enabled platform keycloak
    ! image_selection_enabled platform backstage
  '
  [ "$status" -eq 0 ]
}
@test "matching build inputs reuse immutable cached image without Docker build" {
  run bash -eu -c '
    source "$REPO_ROOT/kubernetes/workflow/image-build-lib.sh"
    CACHE_PUSH_HOST=cache IMAGE_NAMESPACE=platform IMAGE_BUILD_COMMIT_TAG=newcommit IMAGE_BUILD_REQUIRE_COMMIT_TAG=1
    image_build_input_tag() { echo inputs-matching; }
    image_build_tag_exists() { [ "$3" = inputs-matching ]; }
    docker() { echo "docker $*"; }
    image_build_push_ref() { echo "push $1"; }
    image_build_run_docker() { echo UNEXPECTED_BUILD; return 1; }
    image_build_build_and_push_cached app . Dockerfile v1 src-same
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *'docker pull cache/platform/app:inputs-matching'* ]]
  [[ "$output" == *'push cache/platform/app:newcommit'* ]]
  [[ "$output" != *UNEXPECTED_BUILD* ]]
}

@test "each app repository selects only its own workload images" {
  # The sample apps are separate manifests now, so one can be deployed without
  # the other and its images are the only ones that need building.
  printf 'enable_app_repo_sentiment = true\nenable_app_repo_subnetcalc = false\nenable_argocd = true\n' \
    >"${BATS_TEST_TMPDIR}/one-app.tfvars"
  export IMAGE_BUILD_TFVARS_FILES="${BATS_TEST_TMPDIR}/one-app.tfvars"
  run bash -eu -c '
    source "$REPO_ROOT/kubernetes/workflow/image-selection-lib.sh"
    image_selection_enabled workload sentiment-api
    ! image_selection_enabled workload subnetcalc-api
    ! image_selection_enabled workload subnetcalc-frontend
  '
  [ "$status" -eq 0 ]
}
