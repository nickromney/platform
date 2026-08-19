#!/usr/bin/env bats
#
# Guards a class of bug rather than a single call site.
#
# Several tools the platform shells out to are Perl scripts (shasum is the one
# that bit). On a host whose LANG names a locale that is not installed, Perl
# prints a 14-line warning to stderr on every invocation. Nothing fails, so no
# exit code catches it: the output simply fills with warnings, which is how
# hundreds of lines ended up in the middle of a kind apply.
#
# Grepping the repo for "perl" does not find these, because the call sites say
# "shasum". So this asserts the behaviour under a broken locale instead of the
# spelling of the command.

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  # A locale that cannot plausibly be installed, so the assertion holds on any
  # host regardless of which locales it happens to have generated.
  export BROKEN_LOCALE="zz_ZZ.UTF-8"
}

@test "source fingerprinting emits no locale warnings on a host with an uninstalled LANG" {
  run env -u LC_ALL -u LANGUAGE LANG="${BROKEN_LOCALE}" bash -c "
    set -euo pipefail
    export REPO_ROOT='${REPO_ROOT}'
    source '${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh'
    source_fingerprint_tag apps/shared/apphttp >/dev/null
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"perl: warning"* ]]
  [[ "${output}" != *"Setting locale failed"* ]]
}

@test "source fingerprinting is stable across locales" {
  # The digest feeds image tags. If it moved with the host locale, two machines
  # would disagree about whether an image needed rebuilding.
  run bash -c "
    set -euo pipefail
    export REPO_ROOT='${REPO_ROOT}'
    source '${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh'
    a=\"\$(LANG=C source_fingerprint_tag apps/shared/apphttp)\"
    b=\"\$(LANG='${BROKEN_LOCALE}' source_fingerprint_tag apps/shared/apphttp)\"
    [ \"\${a}\" = \"\${b}\" ] || { echo \"digest drifted: \${a} vs \${b}\"; exit 1; }
    printf '%s\n' \"\${a}\"
  "

  [ "${status}" -eq 0 ]
  [[ "${output}" == src-* ]]
}

@test "every shasum call site runs under a forced locale" {
  # Static backstop for call sites this suite does not exercise. shasum is the
  # Perl-backed tool in use here; a new call added outside an LC_ALL=C scope
  # reintroduces the warning class silently.
  # Tracked files only, matching check-bash32-compat.sh. Scanning the worktree
  # instead would sweep .terragrunt-cache, which holds generated copies of these
  # same scripts and reports stale findings after any plan or apply.
  run bash -c "
    cd '${REPO_ROOT}'
    unchecked=0
    while IFS= read -r file; do
      [ -n \"\${file}\" ] || continue
      grep -qE '(^|[^[:alnum:]_])shasum ' \"\${file}\" || continue
      # A file is considered covered if it forces the locale somewhere before
      # or around its shasum use.
      if ! grep -qE 'LC_ALL=C' \"\${file}\"; then
        echo \"no LC_ALL=C in \${file}\"
        unchecked=1
      fi
    done < <(git ls-files '*.sh')
    exit \${unchecked}
  "

  [ "${status}" -eq 0 ]
}
