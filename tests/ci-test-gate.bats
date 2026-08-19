#!/usr/bin/env bats
#
# make test-ci discovers tracked *.bats files minus tests/ci-gate-backlog.txt.
# A new test file is gated the moment it is tracked. Name it in the backlog
# only when it is not yet safe to run in CI.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "list-ci-bats-tests.sh matches git ls-files minus the backlog" {
  local listed expected

  listed="$(cd "${REPO_ROOT}" && scripts/list-ci-bats-tests.sh --execute)"
  expected="$(
    cd "${REPO_ROOT}" && git ls-files '*.bats' | LC_ALL=C sort | grep -vxF -f tests/ci-gate-backlog.txt
  )"

  [ -n "${listed}" ]
  [ "${listed}" = "${expected}" ]
}

@test "Makefile discovers CI_BATS_TESTS instead of listing files by hand" {
  run grep -F 'CI_BATS_TESTS := $(shell "$(LIST_CI_BATS_TESTS)" --execute)' "${REPO_ROOT}/Makefile"

  [ "${status}" -eq 0 ]

  run awk '/^CI_BATS_TESTS :=/,/[^\\]$/' "${REPO_ROOT}/Makefile"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *".bats"* ]]
}

@test "backlog names only files that exist" {
  local stale=""

  while IFS= read -r file; do
    [[ -n "${file}" && "${file}" != \#* ]] || continue
    [ -f "${REPO_ROOT}/${file}" ] || stale="${stale}${file}"$'\n'
  done <"${REPO_ROOT}/tests/ci-gate-backlog.txt"

  if [ -n "${stale}" ]; then
    printf 'listed in tests/ci-gate-backlog.txt but missing from disk:\n%s\n' "${stale}" >&2
  fi
  [ -z "${stale}" ]
}
