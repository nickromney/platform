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
  "would run pre-push local CI gate: make lint && make test-ci" \
  "$@"

if hook_skip_requested; then
  hook_print_skip_and_exit
fi

if [[ "${PLATFORM_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_warn "PLATFORM_LOCAL_CI_IN_PROGRESS=1; skipping run-local-ci.sh to avoid recursive local CI"
  exit 0
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
Platform pre-push local CI gate

Running:
  make lint
  make test-ci

Skip only when you have a reason:
  LEFTHOOK=0 git push
  PLATFORM_SKIP_HOOKS=1 git push
  git push --no-verify
EOF

export PLATFORM_LOCAL_CI_IN_PROGRESS=1
failed_gate=""

if ! make lint; then
  failed_gate="make lint"
elif ! make test-ci; then
  failed_gate="make test-ci"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed: make lint && make test-ci"
