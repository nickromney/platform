#!/usr/bin/env bats
#
# CI_BATS_TESTS in the root Makefile is hand-maintained, so a new test file sits
# outside the gate until someone remembers to add it. That is not hypothetical:
# tests/release-workflow.bats was failing on main with nothing watching it,
# because it had never been listed.
#
# This asserts the list is complete rather than asserting any particular file is
# in it. A file that genuinely should not run in CI can be named in the
# backlog below, which makes the existing gap explicit and reviewable instead
# of silent, and stops it growing.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

# Files still outside the gate. Started at 37 on 2026-08-14; 11 were triaged
# green and added, then 17 more on 2026-08-15, leaving these 9.
#
# They are not merely unlisted -- most are RED. Each safe-to-run file was run in
# isolation on 2026-08-15 and the failing/total count recorded beside it below.
# The 2026-08-14 pass claimed to record these counts and did not, so the size of
# the remaining job was being guessed rather than known. Adding a file to
# CI_BATS_TESTS without fixing it first would simply move its redness into the
# gate, which is the condition this whole effort exists to end.
#
# The six docker entries are untriaged: they reference docker build/run or
# compose, and running them unsupervised risks real side effects.
#
# Adding a new test file? Put it in CI_BATS_TESTS. Do not add it here.
CI_GATE_BACKLOG="tests/backstage-compose.bats
tests/backstage-portal.bats
tests/devcontainer-makefile.bats
tests/grafana-dashboard-quality.bats
tests/platform-workflow-ui.bats
tests/smoke-sentiment-api-image.bats
tests/validate-app-runtime-surfaces.bats
tests/validate-docker-optimization-contracts.bats
tests/vanilla-js-typecheck.bats"

# Measured 2026-08-15, each file run in isolation. fail/total:
#
#   2/4    grafana-dashboard-quality      asserts live Prometheus series
#   2/11   platform-workflow-ui           HANGS -- killed at 300s
#   15/61  vanilla-js-typecheck
#
#   untriaged (docker): backstage-compose, backstage-portal,
#   devcontainer-makefile, smoke-sentiment-api-image,
#   validate-app-runtime-surfaces, validate-docker-optimization-contracts
#
# Two of these need more than a fix to the assertion. grafana-dashboard-quality
# queries a live Grafana/Prometheus, so it can never be hermetic in its current
# shape. platform-workflow-ui does not fail so much as never finish, which is
# worse in a gate than a red test.

is_backlogged() {
  printf '%s\n' "${CI_GATE_BACKLOG}" | grep -qxF "$1"
}

@test "no new tests/*.bats file escapes CI_BATS_TESTS" {
  local listed missing=""

  listed="$(
    cd "${REPO_ROOT}" &&
      awk '/^CI_BATS_TESTS :=/,/[^\\]$/' Makefile |
      grep -oE '(tests|kubernetes/kind/tests)/[A-Za-z0-9._-]+\.bats' |
      sort -u
  )"

  [ -n "${listed}" ]

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    is_backlogged "${file}" && continue
    if ! printf '%s\n' "${listed}" | grep -qxF "${file}"; then
      missing="${missing}${file}"$'\n'
    fi
  done < <(cd "${REPO_ROOT}" && git ls-files 'tests/*.bats')

  if [ -n "${missing}" ]; then
    printf 'not in CI_BATS_TESTS:\n%s\n' "${missing}" >&2
    printf 'Add each to CI_BATS_TESTS in the root Makefile.\n' >&2
  fi

  [ -z "${missing}" ]
}

@test "CI_BATS_TESTS names only files that exist" {
  local stale=""

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    [ -f "${REPO_ROOT}/${file}" ] || stale="${stale}${file}"$'\n'
  done < <(
    cd "${REPO_ROOT}" &&
      awk '/^CI_BATS_TESTS :=/,/[^\\]$/' Makefile |
      grep -oE '(tests|kubernetes/kind/tests)/[A-Za-z0-9._-]+\.bats' |
      sort -u
  )

  if [ -n "${stale}" ]; then
    printf 'listed in CI_BATS_TESTS but missing from disk:\n%s\n' "${stale}" >&2
  fi

  [ -z "${stale}" ]
}
