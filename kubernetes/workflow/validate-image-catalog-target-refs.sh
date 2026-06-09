#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/go/bin:/usr/local/bin:${PATH}"
export GOCACHE="${GOCACHE:-${REPO_ROOT}/.run/go-cache}"

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

args=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --catalog|--tfvars)
      args+=("$1" "$(absolute_path "$2")")
      shift 2
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

exec go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/validate-image-catalog-target-refs "${args[@]}"
