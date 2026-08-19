#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck disable=SC1091
source "${HOOKS_REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Runs the repo local CI gate used by the pre-push hook.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would run pre-push local CI gate: make lint plus the Bats suite" \
  "$@"

if hook_skip_requested; then
  hook_print_skip_and_exit
fi

if [[ "${PLATFORM_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_warn "PLATFORM_LOCAL_CI_IN_PROGRESS=1; skipping run-local-ci.sh to avoid recursive local CI"
  exit 0
fi

cd "${HOOKS_REPO_ROOT}"

# Running the full suite here is the wrong thing, and not for taste reasons.
# git opens the SSH connection to the remote BEFORE running pre-push, so a gate
# that takes ~12 minutes outlives it: the hook passes and the push then fails
# with "Connection to github.com closed by remote host". A gate that prevents
# the operation it guards is not a gate.
#
# GitHub CI no longer runs on pull_request either -- it is main and
# workflow_dispatch only -- so "it will be caught remotely" is not a fallback.
# The full suite has to run locally, just not inside the push.
#
# So: `make test-ci` stamps a receipt naming the exact tree it verified, and
# this hook checks that receipt against the tree being pushed. Full coverage,
# about 90 seconds of hook, and no twelve-minute wait on an unchanged tree.
#
# PLATFORM_LOCAL_CI_FULL=1 runs the whole suite here instead, knowing the push
# itself may then time out.
LOCAL_CI_FULL="${PLATFORM_LOCAL_CI_FULL:-0}"

if [[ "${LOCAL_CI_FULL}" == "1" ]]; then
  gate_label="make lint && make test-ci"
else
  gate_label="make lint && the make test-ci receipt for this tree"
fi

cat <<EOF
Platform pre-push local CI gate

Running:
  ${gate_label}

Run the full suite inside the push instead:
  PLATFORM_LOCAL_CI_FULL=1 git push

Skip only when you have a reason:
  LEFTHOOK=0 git push
  PLATFORM_SKIP_HOOKS=1 git push
  git push --no-verify
EOF

export PLATFORM_LOCAL_CI_IN_PROGRESS=1
failed_gate=""

if ! make lint; then
  failed_gate="make lint"
elif [[ "${LOCAL_CI_FULL}" == "1" ]]; then
  if ! make test-ci; then
    failed_gate="make test-ci"
  fi
elif ! "${HOOKS_REPO_ROOT}/scripts/ci-receipt.sh" --execute --action verify; then
  failed_gate="the make test-ci receipt"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed: ${gate_label}"
