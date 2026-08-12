#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# Make/terragrunt can invoke this with a trimmed PATH, so re-add the usual
# toolchain locations. Homebrew prefixes only exist on macOS; appending rather
# than prepending keeps whatever the caller already resolved (mise shims,
# pacman-installed go) in front.
PATH="${PATH}:/usr/local/go/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
export GOCACHE="${GOCACHE:-${REPO_ROOT}/.run/go-cache}"

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

if [[ "$#" -eq 3 ]]; then
  set -- "$(absolute_path "$1")" "$2" "$3"
fi

exec go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/rewrite-devcontainer-kubeconfig "$@"
