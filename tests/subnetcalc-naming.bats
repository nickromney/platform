#!/usr/bin/env bats
#
# The app is `subnetcalc`. `subnet-calculator` is the old name, and it must not
# come back in source, config, paths or image references.
#
# The scan is over tracked files via git grep rather than rg over REPO_ROOT.
# The old form needed six globs to talk itself out of node_modules, dist and
# lockfiles -- all of them untracked, so git grep never sees them -- and it
# depended on rg being installed to run at all.
#
# What the rename does not reach is history and external names, so those are
# allowlisted individually with the reason recorded. All four were live
# failures: this suite sat outside CI_BATS_TESTS and had gone red unnoticed.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

# Names the separate `subnet-calculator` repository, which is its real name --
# the retired experiments were moved there. Not a stale reference to this app.
ALLOWED="apps/subnetcalc/README.md"

# Carries `! grep -Fq \"subnet-calculator.git\"`, a negative assertion enforcing
# this same policy on the generated workflow. It names the old form in order to
# ban it, exactly as this file does.
ALLOWED="${ALLOWED}
kubernetes/kind/tests/app-repo-sync.bats"

# Historical records, which have to name the old form to describe it: ADR 0001
# states what the tree contained at initial commit 23b2689, and the follow-ups
# plan documents this very rename. Rewriting either would make the record wrong
# rather than current. Prefixes are not dead-checked -- a document may stop
# mentioning the old name without that being a finding.
ALLOWED_PREFIXES="docs/adr/
docs/plans/"

# Excludes itself: naming the pattern to search for it is not a use of it.
scan_matches() {
  git -C "${REPO_ROOT}" grep -l "subnet-calculator" -- \
    . ':(exclude)tests/subnetcalc-naming.bats'
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

@test "tracked source uses subnetcalc rather than subnet-calculator" {
  local unexpected=""

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    is_allowed "${file}" || unexpected="${unexpected}${file}"$'\n'
  done < <(scan_matches)

  if [ -n "${unexpected}" ]; then
    printf 'the retired name subnet-calculator appears in:\n%s\n' "${unexpected}" >&2
    printf 'Rename to subnetcalc, or add the file to ALLOWED with a reason.\n' >&2
  fi

  [ -z "${unexpected}" ]
}

@test "the subnet-calculator allowlist names nothing that has since been renamed" {
  local matches dead=""

  matches="$(scan_matches)"

  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    printf '%s\n' "${matches}" | grep -qxF "${file}" || dead="${dead}${file}"$'\n'
  done <<<"${ALLOWED}"

  if [ -n "${dead}" ]; then
    printf 'allowlisted but no longer mentioning subnet-calculator:\n%s\n' "${dead}" >&2
    printf 'Remove each from ALLOWED; a stale entry is an unreviewed permission.\n' >&2
  fi

  [ -z "${dead}" ]
}
