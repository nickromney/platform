#!/usr/bin/env bats

# The OpenTofu suite is 231s -- a third of the bats gate again -- so it is split:
# `--tier fast` (validations + smoke, 43s) runs in `make test-ci`, and the full
# suite runs on demand or when the Terraform module changes.
#
# Two things are guarded here:
#
# 1. Tier membership is COMPLETE. Every tracked .tftest.hcl must be named in
#    exactly one of FAST_TIER or FULL_ONLY_TIER in the runner. Without this a
#    new test file lands outside both tiers and is run by nothing -- which is
#    precisely how kubernetes/tests/*.bats came to be invisible, and how the
#    Go suites came to be unenforced.
#
# 2. The fast tier actually passes. If tofu is absent this SKIPS rather than
#    fails, because tofu is a heavyweight infra binary a contributor may
#    reasonably not have. The skip is visible in TAP output as
#    `ok N # skip ...`, which is deliberately not the same as a silent pass --
#    see scripts/lint-markdown.sh for the shape being avoided, where a missing
#    tool produced a green exit and no record that nothing had been checked.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  RUNNER="${REPO_ROOT}/terraform/kubernetes/scripts/run-opentofu-tests.sh"
  export RUNNER
}

tier_members() {
  # Extract a bash array literal's entries from the runner without sourcing it.
  local name="$1"
  awk -v name="${name}" '
    $0 ~ "^" name "=\\(" { inside = 1; next }
    inside && /^\)/ { inside = 0 }
    inside { gsub(/[[:space:]]/, "", $0); if ($0 != "") print }
  ' "${RUNNER}"
}

@test "every tracked tftest file belongs to exactly one OpenTofu tier" {
  local fast full declared tracked missing="" duplicated=""

  fast="$(tier_members FAST_TIER)"
  full="$(tier_members FULL_ONLY_TIER)"

  [ -n "${fast}" ]
  [ -n "${full}" ]

  declared="$(printf '%s\n%s\n' "${fast}" "${full}" | sed '/^$/d' | sort)"
  tracked="$(cd "${REPO_ROOT}/terraform/kubernetes" && git ls-files 'tests/*.tftest.hcl' | sort)"

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    printf '%s\n' "${declared}" | grep -qxF "${file}" || missing="${missing}${file}"$'\n'
  done <<<"${tracked}"

  duplicated="$(printf '%s\n' "${declared}" | uniq -d)"

  if [ -n "${missing}" ]; then
    printf 'tftest files in neither FAST_TIER nor FULL_ONLY_TIER:\n%s\n' "${missing}" >&2
    printf 'Add each to one tier in %s\n' "${RUNNER}" >&2
  fi
  if [ -n "${duplicated}" ]; then
    printf 'tftest files in BOTH tiers:\n%s\n' "${duplicated}" >&2
  fi

  [ -z "${missing}" ]
  [ -z "${duplicated}" ]
}

@test "no tier names a tftest file that does not exist" {
  local stale=""

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    [ -f "${REPO_ROOT}/terraform/kubernetes/${file}" ] || stale="${stale}${file}"$'\n'
  done < <(printf '%s\n%s\n' "$(tier_members FAST_TIER)" "$(tier_members FULL_ONLY_TIER)" | sed '/^$/d')

  if [ -n "${stale}" ]; then
    printf 'named in a tier but missing from disk:\n%s\n' "${stale}" >&2
  fi
  [ -z "${stale}" ]
}

@test "the fast OpenTofu tier passes" {
  if ! command -v tofu >/dev/null 2>&1; then
    skip "tofu not installed; the fast OpenTofu tier cannot be vouched for on this host"
  fi

  run "${RUNNER}" --execute --tier fast --timeout-seconds 600
  if [ "${status}" -eq 127 ]; then
    skip "tofu not runnable; the fast OpenTofu tier cannot be vouched for on this host"
  fi

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}" >&2
  fi
  [ "${status}" -eq 0 ]
}
