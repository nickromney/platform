#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/go/bin:/usr/local/bin:${PATH}"
export GOCACHE="${GOCACHE:-${REPO_ROOT}/.run/go-cache}"

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

if [[ "$#" -eq 7 ]]; then
  set -- "$(absolute_path "$1")" "$(absolute_path "$2")" "$3" "$4" "$5" "$6" "$7"
fi

exec go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/render-kind-apiserver-oidc-manifest "$@"
