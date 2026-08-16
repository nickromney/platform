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

# The full suite is the wrong thing to run here, and not for taste reasons.
# git opens the SSH connection to the remote BEFORE running pre-push, so a gate
# that takes ~12 minutes outlives it: the hook passes and the push then fails
# with "Connection to github.com closed by remote host". A gate that prevents
# the operation it guards is not a gate.
#
# So the default is the fast pair -- lint plus the host-portable subset, about 90
# seconds -- and the full suite runs in CI, which #196 wired to pull_request and
# push. Set PLATFORM_LOCAL_CI_FULL=1 to run the whole thing locally anyway,
# knowing the push itself may then time out.
LOCAL_CI_FULL="${PLATFORM_LOCAL_CI_FULL:-0}"
if [[ "${LOCAL_CI_FULL}" == "1" ]]; then
  suite_target="test-ci"
  suite_label="the full Bats suite"
else
  suite_target="test-host-portable"
  suite_label="the host-portable Bats subset (full suite runs in CI)"
fi

cat <<EOF
Platform pre-push local CI gate

Running:
  make lint
  make ${suite_target}   -- ${suite_label}

Run everything locally instead:
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
elif ! make "${suite_target}"; then
  failed_gate="make ${suite_target}"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed: make lint && make ${suite_target}"
