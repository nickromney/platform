#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-status-action-catalog.sh"
}

@test "platform status action catalog renders kind variant actions from supplied facts" {
  run "${SCRIPT}" --records \
    --variant kind \
    --variant-path kubernetes/kind \
    --runtime-present 0 \
    --apply-100-enabled 0 \
    --apply-100-reason "docker not found in PATH" \
    --apply-900-enabled 0 \
    --apply-900-reason "Docker Hub auth missing"

  [ "${status}" -eq 0 ]

  run jq -s -r '
    [
      (any(.[]; .id == "kind-status" and .enabled == true and .dangerous == false and .command == "make -C kubernetes/kind status")),
      (any(.[]; .id == "kind-check-health" and .enabled == false and .reason == "kubernetes/kind is not running" and .dangerous == false)),
      (any(.[]; .id == "kind-reset" and .enabled == false and .reason == "kubernetes/kind is not present" and .dangerous == true)),
      (any(.[]; .id == "kind-apply-100" and .enabled == false and .reason == "docker not found in PATH" and .dangerous == true)),
      (any(.[]; .id == "kind-switch" and .enabled == false and .reason == "Docker Hub auth missing" and .dangerous == true)),
      (any(.[]; .id == "kind-idp-catalog" and .dangerous == false)),
      (any(.[]; .id == "kind-gitea-repo-lifecycle-demo" and .dangerous == false))
    ] | map(tostring) | join("|")
  ' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "true|true|true|true|true|true|true" ]
}

@test "platform status action catalog renders Lima labels and commands" {
  run "${SCRIPT}" --records \
    --variant lima \
    --variant-path kubernetes/lima \
    --runtime-present 1 \
    --apply-100-enabled 1 \
    --apply-100-reason "" \
    --apply-900-enabled 1 \
    --apply-900-reason ""

  [ "${status}" -eq 0 ]
  run jq -s -r '
    [
      (any(.[]; .id == "lima-status" and .label == "Kubernetes Lima status")),
      (any(.[]; .id == "lima-stop" and .command == "make -C kubernetes/lima stop-lima" and .dangerous == false)),
      (any(.[]; .id == "lima-apply-900" and .enabled == true and .reason == null))
    ] | map(tostring) | join("|")
  ' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "true|true|true" ]
}
