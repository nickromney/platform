#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-version.sh"
  export TF_DEFAULTS_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/tf-defaults.sh"
  export KIND_KUBECONFIG="${HOME}/.kube/kind-kind-local.yaml"
}

@test "check-version reports vendored Argo chart apps from live resource labels" {
  if ! command -v kubectl >/dev/null 2>&1; then
    skip "kubectl is required"
  fi

  if ! command -v timeout >/dev/null 2>&1; then
    skip "timeout is required"
  fi

  if [ ! -f "${KIND_KUBECONFIG}" ]; then
    skip "kind kubeconfig not found"
  fi

  if ! KUBECONFIG="${KIND_KUBECONFIG}" kubectl get ns --request-timeout=5s >/dev/null 2>&1; then
    skip "kind cluster is not reachable"
  fi

  local expected_gitea expected_policy_reporter expected_prometheus
  expected_gitea="$(bash -lc "source '${TF_DEFAULTS_SCRIPT}'; tf_default_from_variables gitea_chart_version")"
  expected_policy_reporter="$(bash -lc "source '${TF_DEFAULTS_SCRIPT}'; tf_default_from_variables policy_reporter_chart_version")"
  expected_prometheus="$(bash -lc "source '${TF_DEFAULTS_SCRIPT}'; tf_default_from_variables prometheus_chart_version")"

  run env KUBECONFIG="${KIND_KUBECONFIG}" timeout 300 "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ gitea\ chart[[:space:]]+${expected_gitea}[[:space:]]+${expected_gitea} ]]
  [[ "${output}" =~ policy-reporter[[:space:]]+${expected_policy_reporter}[[:space:]]+${expected_policy_reporter} ]]
  [[ "${output}" =~ prometheus\ chart[[:space:]]+${expected_prometheus}[[:space:]]+${expected_prometheus} ]]
  [[ ! "${output}" =~ gitea\ chart[[:space:]]+${expected_gitea}[[:space:]]+$ ]]
  [[ ! "${output}" =~ policy-reporter[[:space:]]+${expected_policy_reporter}[[:space:]]+$ ]]
  [[ ! "${output}" =~ prometheus\ chart[[:space:]]+${expected_prometheus}[[:space:]]+$ ]]
}
