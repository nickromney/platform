#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "root make help is informational and points to focused Makefiles" {
  run make -C "${REPO_ROOT}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"This root Makefile is informational only."* ]]
  [[ "${output}" == *"make prereqs"* ]]
  [[ "${output}" == *"make test"* ]]
  [[ "${output}" == *"make kubernetes"* ]]
  [[ "${output}" == *"make apps"* ]]
  [[ "${output}" == *"make sdwan"* ]]
}

@test "root prereqs and test are informational entrypoints" {
  run make -C "${REPO_ROOT}" prereqs

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Root prereqs is informational."* ]]
  [[ "${output}" == *"make -C kubernetes/kind prereqs"* ]]

  run make -C "${REPO_ROOT}" test

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Root test is informational."* ]]
  [[ "${output}" == *"make -C sd-wan/lima test"* ]]
}
