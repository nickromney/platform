#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

teardown() {
  rm -rf "${REPO_ROOT}/apps/zz-test-target-surface"
}

@test "make known goals helper reports evaluated MAKE_KNOWN_GOALS additions" {
  fixture="${REPO_ROOT}/apps/zz-test-target-surface"
  mkdir -p "${fixture}"
  cat >"${fixture}/Makefile" <<'MAKEFILE'
MAKE_KNOWN_GOALS := help
MAKE_KNOWN_GOALS += update

.PHONY: update
update:
	@echo update wrapper
MAKEFILE

  run "${REPO_ROOT}/scripts/make-known-goals.sh" --dir "${fixture}" --execute

  [ "${status}" -eq 0 ]
  [[ " ${output} " == *" update "* ]]
}

@test "repo-owned Makefiles load every explicit phony target" {
  run "${REPO_ROOT}/scripts/check-make-target-surfaces.sh" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"repo-owned Makefiles"* ]]
}

@test "target surface audit checks evaluated MAKE_KNOWN_GOALS additions" {
  fixture="${REPO_ROOT}/apps/zz-test-target-surface"
  mkdir -p "${fixture}"
  cat >"${fixture}/Makefile" <<'MAKEFILE'
MAKE_KNOWN_GOALS := help
MAKE_KNOWN_GOALS += missing-real-target
USE_COMMON_HELP := 1

include ../../mk/common.mk
MAKEFILE

  run "${REPO_ROOT}/scripts/check-make-target-surfaces.sh" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"phony target missing from make database: ./apps/zz-test-target-surface missing-real-target"* ]]
}
