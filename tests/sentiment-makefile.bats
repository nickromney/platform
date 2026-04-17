#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "sentiment make help exposes the update workflow" {
  run make -C "${REPO_ROOT}/apps/sentiment" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"update"* ]]
}

@test "sentiment update delegates to each bun dependency root" {
  run make -n -C "${REPO_ROOT}/apps/sentiment" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"cd api-sentiment && bun update --latest"* ]]
  [[ "${output}" == *"cd frontend-react-vite/sentiment-auth-ui && bun update --latest"* ]]
  [[ "${output}" == *"cd frontend-typescript-vite && bun update --latest"* ]]
}
