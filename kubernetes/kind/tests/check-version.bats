#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-version.sh"
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

  run env KUBECONFIG="${KIND_KUBECONFIG}" timeout 300 "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"gitea chart      12.5.0       12.5.0"* ]]
  [[ "${output}" == *"policy-reporter  3.7.3        3.7.3"* ]]
  [[ "${output}" == *"prometheus chart 28.13.0      28.13.0"* ]]
  [[ "${output}" != *"gitea chart                   12.5.0"* ]]
  [[ "${output}" != *"policy-reporter               3.7.3"* ]]
  [[ "${output}" != *"prometheus chart              28.13.0"* ]]
}
