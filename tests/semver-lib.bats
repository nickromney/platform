#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export LIB="${REPO_ROOT}/scripts/lib/semver.sh"
}

@test "version_lt orders dotted numeric versions without GNU sort" {
  run bash -c "source '${LIB}'; version_lt 1.9 1.10"

  [ "${status}" -eq 0 ]

  run bash -c "source '${LIB}'; version_lt 1.10 1.9"

  [ "${status}" -eq 1 ]
}

@test "version_gte treats a leading v as ignorable and equal cores as equal" {
  run bash -c "source '${LIB}'; version_gte v0.32.0 0.32.0"

  [ "${status}" -eq 0 ]

  run bash -c "source '${LIB}'; version_gte 1.2.0 1.2"

  [ "${status}" -eq 0 ]
}

@test "sort_semver returns the highest dotted version from a list" {
  run bash -c "source '${LIB}'; printf '%s\n' 1.9.0 v1.10.0 1.10.0-unused 1.2.3 | grep -v -- '-' | sort_semver | tail -n 1"

  [ "${status}" -eq 0 ]
  [ "${output}" = "v1.10.0" ]
}

@test "version checkers source the portable helper and do not use GNU sort -V" {
  # 1.9 vs 1.10 is the case lexicographic sort and BSD sort both get wrong.
  # These scripts used `sort -V` for it, which is GNU-only and silent on macOS.
  local script
  for script in \
    terraform/kubernetes/scripts/check-provider-version.sh \
    terraform/kubernetes/scripts/check-component-version.sh \
    terraform/kubernetes/scripts/preload-images.sh
  do
    grep -Fq 'scripts/lib/semver.sh' "${REPO_ROOT}/${script}"
    if grep -nE '(^|[[:space:];|&])sort[[:space:]]+-V' "${REPO_ROOT}/${script}"; then
      echo "${script} still uses GNU sort -V" >&2
      return 1
    fi
  done
}
