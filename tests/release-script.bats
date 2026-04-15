#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${TEST_REPO}/scripts"
  cp "${REPO_ROOT}/scripts/release.sh" "${TEST_REPO}/scripts/release.sh"
  chmod +x "${TEST_REPO}/scripts/release.sh"

  git -C "${TEST_REPO}" init -q
  git -C "${TEST_REPO}" config user.email "test@example.com"
  git -C "${TEST_REPO}" config user.name "Test User"
  printf '%s\n' "0.3.0" >"${TEST_REPO}/VERSION"
  git -C "${TEST_REPO}" add VERSION scripts/release.sh
  git -C "${TEST_REPO}" commit -q -m "initial"
}

@test "release script help advertises standard shell interface" {
  run "${TEST_REPO}/scripts/release.sh" --help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
  [[ "${output}" == *"--dry-run"* ]]
  [[ "${output}" == *"--execute"* ]]
}

@test "release dry-run resumes after VERSION was already written by a failed release" {
  printf '%s\n' "0.1.0" >"${TEST_REPO}/VERSION"

  run "${TEST_REPO}/scripts/release.sh" --dry-run 0.1.0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"+ make check-version"* ]]
  [[ "${output}" == *"+ git commit -m chore(release): bump version to 0.1.0"* ]]
  [[ "${output}" != *"already prepared"* ]]
}

@test "release execute commits already-written target VERSION" {
  printf '%s\n' "0.1.0" >"${TEST_REPO}/VERSION"

  run env SKIP_CHECKS=1 "${TEST_REPO}/scripts/release.sh" --execute 0.1.0

  [ "${status}" -eq 0 ]

  run git -C "${TEST_REPO}" log -1 --format=%s

  [ "${status}" -eq 0 ]
  [ "${output}" = "chore(release): bump version to 0.1.0" ]

  run git -C "${TEST_REPO}" status --short

  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "release execute rejects unrelated dirty files" {
  printf '%s\n' "0.1.0" >"${TEST_REPO}/VERSION"
  printf '%s\n' "dirty" >"${TEST_REPO}/README.md"

  run env SKIP_CHECKS=1 "${TEST_REPO}/scripts/release.sh" --execute 0.1.0

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"git worktree must be clean before a real release"* ]]
}
