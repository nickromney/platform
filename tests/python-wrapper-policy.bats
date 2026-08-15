#!/usr/bin/env bats
#
# Host-side code should not reach for a bare `python3`, because nothing pins it:
# it is whatever the host happens to have, or nothing at all.
#
# Two things about this file are deliberate, both learned from it being broken:
#
# 1. It excludes itself from the scan by pathspec rather than by allowlist. The
#    line below names the pattern in order to search for it; it does not call
#    it. Before this, the file matched its own grep and was absent from the
#    allowlist, so the test could not pass on any tree, ever. It sat outside
#    CI_BATS_TESTS, so nothing reported that.
#
# 2. The allowlist is asserted to be live, not just sufficient. It had rotted in
#    both directions: six entries permitted nothing at all (apps/apim-simulator/,
#    docs/, kubernetes/workflow/, tools/platform-workflow-ui/ and two test files
#    that had since dropped their python3 use), while ten tracked files used
#    python3 with only four of them named. An allowlist nobody can see rotting
#    grows permissions it was never reviewed for.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

# Container and toolchain definitions that install or verify a python3.
ALLOWED=".devcontainer/Dockerfile
.devcontainer/check-toolchain-surface.sh
apps/backstage/Dockerfile"

# Audit tooling that names the pattern it audits, in the same way this file does.
ALLOWED="${ALLOWED}
kubernetes/kind/tests/check-version.bats
scripts/audit-shell-scripts.sh
tests/audit-shell-scripts.bats"

# Bats suites using python3 as a test helper. Test scaffolding rather than
# host-side code, so the pin argument above does not apply to them. Note only
# tests/app-healthcheck-commands.bats guards with `command -v python3`; the rest
# hard-depend on it being present. That holds on ubuntu-latest and in the
# devcontainer, and is worth revisiting if either stops shipping it.
ALLOWED="${ALLOWED}
tests/app-healthcheck-commands.bats
tests/app-layout-consistency.bats
tests/application-surface-projection.bats
tests/docs-content-current.bats
tests/langfuse-demos.bats
tests/sso-e2e-app-toggles.bats
tests/subnetcalc-go-only.bats
tests/validate-app-runtime-surfaces.bats
tests/validate-docker-optimization-contracts.bats
tests/vanilla-js-typecheck.bats"

# Recorded run artifacts. History, not code, and not editable to comply.
ALLOWED_PREFIXES="tests/artifacts/"

# Tracked files referencing python3, excluding this one -- see note 1 above.
scan_matches() {
  git -C "${REPO_ROOT}" grep -l "python3" -- \
    . ':(exclude)tests/python-wrapper-policy.bats'
}

is_allowed() {
  printf '%s\n' "${ALLOWED}" | grep -qxF "$1" && return 0
  local prefix
  while IFS= read -r prefix; do
    [ -n "${prefix}" ] || continue
    [[ "$1" == "${prefix}"* ]] && return 0
  done <<<"${ALLOWED_PREFIXES}"
  return 1
}

@test "tracked host-side code avoids bare python references outside approved exceptions" {
  local unexpected=""

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    is_allowed "${file}" || unexpected="${unexpected}${file}"$'\n'
  done < <(scan_matches)

  if [ -n "${unexpected}" ]; then
    printf 'bare python3 outside the allowlist:\n%s\n' "${unexpected}" >&2
    printf 'Use a pinned interpreter, or add the file to ALLOWED with a reason.\n' >&2
  fi

  [ -z "${unexpected}" ]
}

@test "the bare-python allowlist names nothing that has stopped using python3" {
  local matches dead=""

  matches="$(scan_matches)"
  [ -n "${matches}" ]

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    printf '%s\n' "${matches}" | grep -qxF "${file}" || dead="${dead}${file}"$'\n'
  done <<<"${ALLOWED}"

  if [ -n "${dead}" ]; then
    printf 'allowlisted but no longer using python3:\n%s\n' "${dead}" >&2
    printf 'Remove each from ALLOWED; a stale entry is an unreviewed permission.\n' >&2
  fi

  [ -z "${dead}" ]
}
