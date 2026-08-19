#!/usr/bin/env bash
set -euo pipefail

# A receipt records that the full gate passed against one exact working tree.
#
# The pre-push hook cannot simply run the full gate: git opens the SSH
# connection to the remote BEFORE running pre-push, so a ~12 minute hook
# outlives it and the push dies with "Connection closed by remote host" after
# the gate has already passed. See scripts/hooks/run-local-ci.sh.
#
# So the gate runs when you ask for it, stamps what it verified, and pre-push
# checks that stamp against the tree it is about to push. That keeps the full
# suite local without putting twelve minutes inside the push.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

RECEIPT_FILE="${CI_RECEIPT_FILE:-${REPO_ROOT}/.run/ci-receipt.json}"
ACTION=""

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<EOF
Usage: ${0##*/} --action stamp|verify|fingerprint [--dry-run] [--execute]

Record or check that the full local gate passed for the current working tree.

  stamp        write ${RECEIPT_FILE} for the current tree
  verify       exit 0 only if the receipt matches the current tree
  fingerprint  print the current tree fingerprint and exit

$(shell_cli_standard_options)
EOF
}

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      [[ $# -ge 2 ]] || {
        printf '%s: --action requires a value\n' "${0##*/}" >&2
        exit 2
      }
      ACTION="$2"
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

shell_cli_handle_standard_no_args usage \
  "would ${ACTION:-check} the local gate receipt at ${RECEIPT_FILE}" \
  "${args[@]+"${args[@]}"}"

case "${ACTION}" in
  stamp | verify | fingerprint) ;;
  "")
    printf '%s: --action is required\n' "${0##*/}" >&2
    exit 2
    ;;
  *)
    printf '%s: unknown action: %s\n' "${0##*/}" "${ACTION}" >&2
    exit 2
    ;;
esac

# The fingerprint is the CONTENT of the working tree, not the commit it sits on.
#
# That distinction is the whole design. The normal sequence is: run the gate,
# commit, push. Committing changes HEAD and empties `git diff HEAD` while
# changing no file at all, so any fingerprint built from HEAD or from a diff
# would invalidate itself at the commit and demand a second twelve-minute run
# for a tree the gate had already verified. It must also stay sensitive to
# uncommitted and untracked edits, which is what makes "I ran the tests" true at
# push time rather than merely once.
#
# git's own tree object is exactly that content hash. Building it in a throwaway
# index leaves the real index untouched: `git add -A` there stages working-tree
# content (honouring .gitignore, so untracked-but-not-ignored files count and
# ignored ones do not), and `git write-tree` hashes it. Blobs land in
# .git/objects unreferenced and are collected by gc, the same as `git stash
# create`.
tree_fingerprint() {
  cd "${REPO_ROOT}"
  local temp_index
  temp_index="$(mktemp "${TMPDIR:-/tmp}/ci-receipt-index.XXXXXX")"
  trap 'rm -f "${temp_index}"' RETURN
  GIT_INDEX_FILE="${temp_index}" git read-tree HEAD
  GIT_INDEX_FILE="${temp_index}" git add -A
  # The receipt must never be an input to its own fingerprint, or stamping
  # would immediately invalidate what it just stamped. Living under the
  # gitignored .run/ already achieves that here; excluding it explicitly means
  # the mechanism does not silently depend on that entry staying in .gitignore.
  local receipt_relative="${RECEIPT_FILE#"${REPO_ROOT}/"}"
  GIT_INDEX_FILE="${temp_index}" git rm --cached --quiet --ignore-unmatch -- \
    "${receipt_relative}" >/dev/null 2>&1 || true
  GIT_INDEX_FILE="${temp_index}" git write-tree
}

case "${ACTION}" in
  fingerprint)
    tree_fingerprint
    ;;

  stamp)
    fingerprint="$(tree_fingerprint)"
    mkdir -p "$(dirname "${RECEIPT_FILE}")"
    # No timestamp in the digest, and none used for validity: a receipt is
    # valid because the tree still matches, not because it is recent. The
    # recorded time and commit are for the message pre-push prints.
    cat >"${RECEIPT_FILE}" <<JSON
{
  "fingerprint": "${fingerprint}",
  "head": "$(git -C "${REPO_ROOT}" rev-parse --short HEAD)",
  "stamped_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
    printf 'OK   gate receipt stamped for %s\n' "${fingerprint:0:12}"
    ;;

  verify)
    if [[ ! -f "${RECEIPT_FILE}" ]]; then
      printf 'no gate receipt at %s\n' "${RECEIPT_FILE}" >&2
      printf 'run: make test-ci\n' >&2
      exit 1
    fi

    recorded="$(sed -n 's/.*"fingerprint": "\([^"]*\)".*/\1/p' "${RECEIPT_FILE}")"
    recorded_head="$(sed -n 's/.*"head": "\([^"]*\)".*/\1/p' "${RECEIPT_FILE}")"
    recorded_at="$(sed -n 's/.*"stamped_at": "\([^"]*\)".*/\1/p' "${RECEIPT_FILE}")"
    current="$(tree_fingerprint)"

    if [[ "${recorded}" != "${current}" ]]; then
      printf 'gate receipt does not match this tree\n' >&2
      printf '  receipt: %s (%s, %s)\n' "${recorded:0:12}" "${recorded_head:-unknown}" "${recorded_at:-unknown}" >&2
      printf '  tree:    %s\n' "${current:0:12}" >&2
      printf 'run: make test-ci\n' >&2
      exit 1
    fi

    printf 'OK   gate receipt current for %s (%s)\n' "${current:0:12}" "${recorded_head:-unknown}"
    ;;
esac
