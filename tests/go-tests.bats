#!/usr/bin/env bats

# The repo carries ~9.5k lines of Go tests across 17 modules, and until this
# file existed NOTHING ran them -- not `make test-ci`, not `make lint`, and not
# either CI job. mk/go-app-core.mk and mk/shared-go-module.mk define `go test`
# targets, but they serve `make -C apps/<name>/app test`, which no gate invokes.
#
# The cost of that gap was already realised: tools/platform-tui carried 29 tests
# with two of them RED, expecting the IDP demo bundle's resource profile to be
# local-idp-12gb after #135 moved it to local-idp-16gb. Stale assertions in a
# file nothing runs -- the same class, and the same cause, as the four reds the
# #199 triage found once kubernetes/*/tests entered the gate.
#
# Module discovery is `git ls-files '*go.mod'` rather than a list, so a new Go
# module is covered the moment it is tracked. There is deliberately no companion
# "did you add it to the list" guard, because there is no list to fall out of.
#
# Cost measured 2026-08-17 on an M4: 9s with a cold test cache, 2s warm.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "go is available to the gate" {
  # Hard failure, not a skip. A silent skip is how a gate reports green while
  # checking nothing -- see scripts/lint-markdown.sh for the shape being avoided.
  run command -v go
  if [ "${status}" -ne 0 ]; then
    printf 'go not found in PATH.\n' >&2
    printf 'The Go test suites cannot run, so this gate cannot vouch for them.\n' >&2
    printf 'Install Go (see scripts/install-tool-hints.sh) or run make test-ci on a host with it.\n' >&2
  fi
  [ "${status}" -eq 0 ]
}

@test "every tracked Go module passes its own test suite" {
  local failures="" modules=0

  while IFS= read -r gomod; do
    [ -n "${gomod}" ] || continue
    local dir="${REPO_ROOT}/$(dirname "${gomod}")"
    modules=$((modules + 1))

    run env -C "${dir}" go test ./...
    if [ "${status}" -ne 0 ]; then
      failures="${failures}$(dirname "${gomod}")"$'\n'
      printf -- '--- %s ---\n%s\n' "$(dirname "${gomod}")" "${output}" >&2
    fi
  done < <(cd "${REPO_ROOT}" && git ls-files '*go.mod')

  # Guard the discovery itself: a globbing change that silently matched nothing
  # would otherwise make this test pass while running zero suites.
  [ "${modules}" -ge 10 ]

  if [ -n "${failures}" ]; then
    printf 'Go modules with failing tests:\n%s\n' "${failures}" >&2
  fi
  [ -z "${failures}" ]
}
