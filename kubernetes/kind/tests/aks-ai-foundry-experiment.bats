#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export EXPERIMENT_ROOT="${REPO_ROOT}/experiments/kind-aks-ai-foundry"
}

@test "experiment up dry-run previews the brokered workload path without mutation" {
  run make -C "${EXPERIMENT_ROOT}" up DRY_RUN=1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"auth-chat-aks-sim -> agentgateway -> apim-simulator -> aifoundry-simulator"* ]]
  [[ "${output}" == *"would start external APIM and AI Foundry containers"* ]]
  [[ "${output}" == *"would apply AKS-shaped Kind resources"* ]]
}

@test "experiment scripts expose the standard shell entrypoint interface" {
  local script_name

  for script_name in up check down; do
    run "${EXPERIMENT_ROOT}/scripts/${script_name}.sh" --help

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage: ${script_name}.sh"* ]]
    [[ "${output}" == *"--dry-run"* ]]
    [[ "${output}" == *"--execute"* ]]
  done

  run "${EXPERIMENT_ROOT}/scripts/check.sh" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would verify the live brokered request path"* ]]
}

@test "experiment documentation exposes the lifecycle and honest AKS boundary" {
  run make -C "${EXPERIMENT_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make up [DRY_RUN=1]"* ]]
  [[ "${output}" == *"make check"* ]]
  [[ "${output}" == *"make down [DRY_RUN=1]"* ]]

  run cat "${EXPERIMENT_ROOT}/README.md"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"AKS-shaped, not an AKS emulator"* ]]
  [[ "${output}" == *"auth-chat-aks-sim -> agentgateway -> apim-simulator -> aifoundry-simulator"* ]]
  [[ "${output}" == *"does not simulate the AKS managed control plane"* ]]

  run grep -F "experiments/kind-aks-ai-foundry" "${REPO_ROOT}/README.md"
  [ "${status}" -eq 0 ]
}

@test "live experiment serves an AKS-shaped workload through APIM and AI Foundry" {
  if [[ "${KIND_AKS_AI_FOUNDRY_LIVE:-0}" != "1" ]]; then
    skip "set KIND_AKS_AI_FOUNDRY_LIVE=1 to run the Docker and Kind experiment"
  fi

  run make -C "${EXPERIMENT_ROOT}" up
  [ "${status}" -eq 0 ]

  run make -C "${EXPERIMENT_ROOT}" check
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"AKS-shaped worker placement: ok"* ]]
  [[ "${output}" == *"APIM rejects missing subscription key: 401"* ]]
  [[ "${output}" == *"direct external egress from workload: denied"* ]]
  [[ "${output}" == *"auth-chat model status: ok"* ]]
  [[ "${output}" == *"APIM trace upstream: http://aifoundry-simulator:8000/openai/v1/chat/completions"* ]]
}

@test "live experiment down removes owned state and up reconverges it" {
  if [[ "${KIND_AKS_AI_FOUNDRY_LIVE:-0}" != "1" ]]; then
    skip "set KIND_AKS_AI_FOUNDRY_LIVE=1 to run the Docker and Kind experiment"
  fi

  run make -C "${EXPERIMENT_ROOT}" down
  [ "${status}" -eq 0 ]

  run kubectl --kubeconfig "${HOME}/.kube/kind-kind-local.yaml" \
    --context kind-kind-local get namespace aks-sim
  [ "${status}" -ne 0 ]

  run docker compose --project-directory "${EXPERIMENT_ROOT}" \
    -f "${EXPERIMENT_ROOT}/compose.yml" ps --services --filter status=running
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]

  run make -C "${EXPERIMENT_ROOT}" up
  [ "${status}" -eq 0 ]
}
