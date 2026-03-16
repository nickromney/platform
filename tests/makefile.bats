#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "root make help is informational and points to focused Makefiles" {
  run make -C "${REPO_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"This root Makefile is informational only."* ]]
  [[ "${output}" == *"make kubernetes"* ]]
  [[ "${output}" == *"make apps"* ]]
  [[ "${output}" == *"make sdwan"* ]]
}
