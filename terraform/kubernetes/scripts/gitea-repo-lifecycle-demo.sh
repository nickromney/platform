#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:30090}"
GITEA_OWNER="${GITEA_OWNER:-platform}"
REPO_NAME="${REPO_NAME:-hello-platform}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--repo NAME]

Demonstrates the local internal-Git lifecycle: check whether a repo exists,
show the create path, and print clone/promotion commands for GitOps use.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  case "$1" in
    --repo)
      REPO_NAME="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would inspect the Gitea repo lifecycle for ${GITEA_OWNER}/${REPO_NAME}"

command -v curl >/dev/null 2>&1 || fail "curl not found in PATH"

api_url="${GITEA_URL%/}/api/v1/repos/${GITEA_OWNER}/${REPO_NAME}"
code="$(curl -sS -o /dev/null -w '%{http_code}' "${api_url}" || true)"

case "${code}" in
  200)
    ok "repo exists: ${GITEA_OWNER}/${REPO_NAME}"
    ;;
  404)
    ok "repo not found yet: ${GITEA_OWNER}/${REPO_NAME}"
    ;;
  *)
    fail "unexpected Gitea API status ${code} for ${api_url}"
    ;;
esac

cat <<EOF
clone_ssh=ssh://git@127.0.0.1:30022/${GITEA_OWNER}/${REPO_NAME}.git
clone_http=${GITEA_URL%/}/${GITEA_OWNER}/${REPO_NAME}.git
promotion_flow=commit desired state, push to Gitea, let Argo CD reconcile
EOF
