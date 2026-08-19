#!/usr/bin/env bash
# Shared Bats helpers. Source from a test with:
#   source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
# Then call setup_repo_root from setup().

setup_repo_root() {
  local dir
  dir="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  while [[ "${dir}" != "/" ]]; do
    if [[ -f "${dir}/Makefile" && -d "${dir}/apps" ]]; then
      export REPO_ROOT="${dir}"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  echo "could not find repo root from ${BATS_TEST_FILENAME}" >&2
  return 1
}
