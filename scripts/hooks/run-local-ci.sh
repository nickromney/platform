#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

if hook_skip_requested; then
  hook_print_skip_and_exit
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

