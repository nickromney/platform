#!/usr/bin/env bats
#
# `make lint` used to hardcode eight `$(MAKE) --no-print-directory lint-*` lines,
# and exactly one of them -- lint-shellcheck -- had a guard asserting it was
# still there (tests/audit-shell-scripts.bats, added by #200). Delete any of the
# other seven and `make lint`, `make test-ci` and CI all stayed green while that
# linter silently stopped running. The defect #200 exists to prevent was still
# live for 7 of 8 linters.
#
# The fix is one source of truth -- LINTERS in the root Makefile -- which
# generates the composite recipe. This file asserts that source of truth cannot
# drift, in both directions:
#
#   * the composite is generated from LINTERS, not hand-listed
#   * LINTERS plus the explicitly-excluded set covers every lint-* target, so a
#     target dropped from LINTERS is named as unreachable rather than forgotten
#   * every scripts/lint-*.sh on disk is reached by something in LINTERS, so a
#     new linter script with no wiring fails the gate
#
# It therefore cannot go stale when a linter is added, which is the property the
# single-target grep it replaces did not have.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

# First `NAME := ...` / `NAME ?= ...` / `NAME = ...` value, verbatim.
makefile_var() {
  sed -n "s/^$1[[:space:]]*[:?]\{0,1\}=[[:space:]]*//p" "${REPO_ROOT}/Makefile" |
    head -n 1
}

# The tab-indented recipe lines of a target.
makefile_recipe() {
  awk -v target="$1:" '
    $0 == target { collecting = 1; next }
    collecting && /^\t/ { print; next }
    collecting { exit }
  ' "${REPO_ROOT}/Makefile"
}

# Every scripts/*.sh a target reaches, resolving $(VAR) indirection one level.
recipe_scripts() {
  local body value var

  body="$(makefile_recipe "$1")"

  printf '%s\n' "${body}" |
    grep -oE '\$\([A-Z0-9_]+\)' |
    sed 's/^\$(//; s/)$//' |
    sort -u |
    while IFS= read -r var; do
      [ -n "${var}" ] || continue
      value="$(makefile_var "${var}")"
      case "${value}" in
        scripts/*.sh) printf '%s\n' "${value}" ;;
      esac
    done

  printf '%s\n' "${body}" | grep -oE 'scripts/[A-Za-z0-9._/-]+\.sh' || true
}

# lint-* targets defined in the Makefile, with the lint- prefix stripped.
lint_targets() {
  grep -oE '^lint-[a-z0-9][a-z0-9-]*:' "${REPO_ROOT}/Makefile" |
    sed 's/^lint-//; s/:$//' |
    sort -u
}

@test "the make lint composite is generated from LINTERS, not hand-listed" {
  # The hand-listed form is the defect: eight independent lines, one guarded.
  # Generating the recipe means there is a single list to guard, and the checks
  # below guard it.
  local recipe

  recipe="$(makefile_recipe lint)"

  [ -n "${recipe}" ]
  [[ "${recipe}" == *'$(foreach linter,$(LINTERS)'* ]]
  [[ "${recipe}" == *'lint-$(linter)'* ]]
}

@test "LINTERS is a non-empty list and every entry is a real target" {
  local linters linter missing=""

  linters="$(makefile_var LINTERS)"

  [ -n "${linters}" ]

  for linter in ${linters}; do
    if [ -z "$(makefile_recipe "lint-${linter}")" ]; then
      missing="${missing}lint-${linter}"$'\n'
    fi
  done

  if [ -n "${missing}" ]; then
    printf 'in LINTERS but has no lint-* target with a recipe:\n%s\n' "${missing}" >&2
  fi

  [ -z "${missing}" ]
}

@test "no lint-* target escapes make lint without being declared excluded" {
  # The anti-drift check. Removing a linter from LINTERS leaves its target
  # defined but unreachable from `make lint`, and this names it. Removing a
  # linter on purpose means deleting the target too, or declaring it in
  # LINTERS_NOT_IN_COMPOSITE with a reason -- either way it is reviewable
  # instead of silent.
  local composite excluded known target orphaned="" phantom=""

  composite="$(makefile_var LINTERS)"
  excluded="$(makefile_var LINTERS_NOT_IN_COMPOSITE)"
  known="$(printf '%s\n%s\n' "${composite}" "${excluded}" | tr ' ' '\n' | grep -v '^$' | sort -u)"

  [ -n "${composite}" ]
  [ -n "${excluded}" ]

  while IFS= read -r target; do
    [ -n "${target}" ] || continue
    printf '%s\n' "${known}" | grep -qxF "${target}" ||
      orphaned="${orphaned}lint-${target}"$'\n'
  done < <(lint_targets)

  while IFS= read -r target; do
    [ -n "${target}" ] || continue
    lint_targets | grep -qxF "${target}" ||
      phantom="${phantom}lint-${target}"$'\n'
  done < <(printf '%s\n' "${known}")

  if [ -n "${orphaned}" ]; then
    printf 'defined but never run by `make lint`:\n%s\n' "${orphaned}" >&2
    printf 'Add it to LINTERS, or to LINTERS_NOT_IN_COMPOSITE with a reason.\n' >&2
  fi
  if [ -n "${phantom}" ]; then
    printf 'named in LINTERS/LINTERS_NOT_IN_COMPOSITE but no such target:\n%s\n' "${phantom}" >&2
  fi

  [ -z "${orphaned}" ]
  [ -z "${phantom}" ]
}

@test "the -live linters stay out of make lint" {
  # lint-cilium-live and lint-kyverno-live run the same validators in --mode live
  # against a cluster. `make lint` has to work on a laptop with nothing running,
  # so they are excluded on purpose -- but the exclusion has to be the only way
  # a linter leaves the composite, or the exclusion list becomes a hiding place.
  local linters excluded linter

  linters="$(makefile_var LINTERS)"
  excluded="$(makefile_var LINTERS_NOT_IN_COMPOSITE)"

  for linter in ${linters}; do
    [[ "${linter}" != *-live ]]
  done

  for linter in ${excluded}; do
    [[ "${linter}" == *-live ]]
  done
}

@test "every scripts/lint-*.sh on disk is reached by make lint" {
  # The half a Makefile-only check cannot see: a linter script added to the repo
  # with no Makefile wiring at all. Nothing else in the tree would notice.
  local linters linter reached script unreached=""

  linters="$(makefile_var LINTERS)"
  reached="$(
    for linter in ${linters}; do
      recipe_scripts "lint-${linter}"
    done | sort -u
  )"

  [ -n "${reached}" ]

  # Tracked files plus the working tree: a linter script that has been written
  # but not yet committed is exactly when the wiring is most likely missing, and
  # `git ls-files` alone would not see it.
  while IFS= read -r script; do
    [ -n "${script}" ] || continue
    printf '%s\n' "${reached}" | grep -qxF "${script}" ||
      unreached="${unreached}${script}"$'\n'
  done < <(
    cd "${REPO_ROOT}" && {
      git ls-files 'scripts/lint-*.sh'
      ls scripts/lint-*.sh 2>/dev/null
    } | sort -u
  )

  if [ -n "${unreached}" ]; then
    printf 'lint script on disk that `make lint` never runs:\n%s\n' "${unreached}" >&2
    printf 'Give it a lint-<name> target and add <name> to LINTERS.\n' >&2
  fi

  [ -z "${unreached}" ]
}

@test "every script make lint reaches exists on disk" {
  # The mirror: a renamed or deleted script leaves a target whose recipe points
  # at nothing, and make would only find out when someone ran that linter.
  local linters linter script missing=""

  linters="$(makefile_var LINTERS)"

  while IFS= read -r script; do
    [ -n "${script}" ] || continue
    [ -x "${REPO_ROOT}/${script}" ] || [ -f "${REPO_ROOT}/${script}" ] ||
      missing="${missing}${script}"$'\n'
  done < <(
    for linter in ${linters}; do
      recipe_scripts "lint-${linter}"
    done | sort -u
  )

  if [ -n "${missing}" ]; then
    printf 'referenced by a lint-* target but not on disk:\n%s\n' "${missing}" >&2
  fi

  [ -z "${missing}" ]
}

@test "make lint really invokes all eight linter scripts" {
  # Structure is not behaviour. `make -n lint` still recurses (recipe lines
  # containing $(MAKE) run under -n) and each sub-make prints, without running,
  # the script it would execute. So this observes the composite actually
  # reaching every linter rather than inferring it from the text.
  local linters linter script

  linters="$(makefile_var LINTERS)"

  run make -C "${REPO_ROOT}" --no-print-directory -n lint

  [ "${status}" -eq 0 ]

  for linter in ${linters}; do
    while IFS= read -r script; do
      [ -n "${script}" ] || continue
      [[ "${output}" == *"${script}"* ]] || {
        printf 'make -n lint never reached %s (for lint-%s)\n' "${script}" "${linter}" >&2
        false
      }
    done < <(recipe_scripts "lint-${linter}")
  done
}
