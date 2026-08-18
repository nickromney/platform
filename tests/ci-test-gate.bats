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
# green and added, then 18 more on 2026-08-15, leaving these 8.
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
#
# 2026-08-15, second pass: this guard only ever enumerated `tests/*.bats`, so it
# could not see `kubernetes/*/tests/*.bats` at all -- 49 of those 55 files were
# outside the gate and the completeness check had no way to say so. That is the
# same defect the guard exists to catch, one level up. Enumeration now covers
# both trees.
#
# 2026-08-16: the 47 that pass added left UNTRIAGED are now triaged, by the same
# method #199 used. 44 were safe to run and each was run in isolation; 40 were
# green and 4 were red. All four reds were STALE ASSERTIONS, not product bugs,
# and every one of them was invisible precisely because the file was outside the
# gate:
#
#   lima/manage-kubeconfig      asserted context `lima-k3s`; it was renamed
#                               `limavm-k3s` and every other test in the file
#                               was updated. Fixed.
#   kind/gitops-refresh         asserted the literal `SECONDS + 300` after the
#                               wait moved behind local.platform_wait_seconds so
#                               PLATFORM_TIMEOUT_SCALE could stretch it. Now
#                               asserts the local, and that it is 300 at scale 1.
#   kind/hubble-observe         asserted "observing namespace <ns>" after the
#                               emitter was reworded to "<ns>: capture iteration
#                               i/n". Two tests. Now matched by shape.
#   kind/check-version          called coreutils `timeout`, which macOS does not
#                               ship, so it failed on `env: timeout: not found`
#                               rather than on its subject. Two sibling tests in
#                               the same file already carried that skip guard.
#
# 2026-08-16, later: the last three are in too. They were held back as
# "docker build/run/compose", but that classification came from grepping for the
# word rather than from reading them: docker-safe-clean and docker-prune-estimate
# stub docker entirely and only assert on the commands they would print, and
# aks-ai-foundry-experiment gates its two live tests behind
# KIND_AKS_AI_FOUNDRY_LIVE=1, so they skip by default. All three run in about a
# second. The kubernetes/*/tests backlog is now empty.
#
# 2026-08-17, third pass -- and the same defect a third time. The second pass
# widened the enumeration glob by exactly one directory level, from
# `tests/*.bats` to `tests/*.bats` plus `kubernetes/*/tests/*.bats`. That still
# could not see `kubernetes/tests/*.bats`, which is one level SHORTER than the
# second pattern and does not match the first: four files (host-gateway-proxy,
# k3s-bootstrap-lib, k3s-registries-lib, sync-local-image-cache) were neither
# gated nor backlogged, and nothing in the repo ran them. All four were green
# and cost ~2s together.
#
# The lesson is that a glob pair is not a completeness check -- it encodes a
# guess about where tests live, and every widening is one more guess. This now
# enumerates `git ls-files '*.bats'` with no path shape at all, so the only way
# to be outside the gate is to be named in CI_GATE_BACKLOG above. A new
# directory cannot hide.
#
# The extraction regex had the same shape problem and would have MIS-PARSED the
# fix: `grep -oE '(tests|kubernetes/[a-z0-9-]+/tests)/...'` matches the inner
# `tests/...` of `kubernetes/tests/foo.bats` and yields the wrong path, so the
# guard would have reported a file missing that was in fact listed. Tokenising
# the Makefile block and filtering on `.bats` drops the assumption entirely.
CI_GATE_BACKLOG="tests/backstage-compose.bats
tests/backstage-portal.bats
tests/devcontainer-makefile.bats
tests/grafana-dashboard-quality.bats
tests/platform-workflow-ui.bats
tests/smoke-sentiment-api-image.bats
tests/validate-app-runtime-surfaces.bats
tests/validate-docker-optimization-contracts.bats"

# Measured 2026-08-15, each file run in isolation. fail/total:
#
#   2/4    grafana-dashboard-quality      asserts live Prometheus series
#   2/11   platform-workflow-ui           HANGS -- killed at 300s
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

@test "no tracked .bats file anywhere escapes CI_BATS_TESTS" {
  local listed missing=""

  listed="$(
    cd "${REPO_ROOT}" &&
      awk '/^CI_BATS_TESTS :=/,/[^\\]$/' Makefile |
      tr -s ' \t\\' '\n' |
      grep -E '\.bats$' |
      sort -u
  )"

  [ -n "${listed}" ]

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    is_backlogged "${file}" && continue
    if ! printf '%s\n' "${listed}" | grep -qxF "${file}"; then
      missing="${missing}${file}"$'\n'
    fi
  done < <(cd "${REPO_ROOT}" && git ls-files '*.bats')

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
      tr -s ' \t\\' '\n' |
      grep -E '\.bats$' |
      sort -u
  )

  if [ -n "${stale}" ]; then
    printf 'listed in CI_BATS_TESTS but missing from disk:\n%s\n' "${stale}" >&2
  fi

  [ -z "${stale}" ]
}
