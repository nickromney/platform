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

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] SOURCE_PATH RENDERED_PATH ISSUER_URL CLIENT_ID CA_PATH DEX_HOST GATEWAY_IP

Renders the kind kube-apiserver static manifest with OIDC flags and managed
host aliases.

$(shell_cli_standard_options)
EOF
}

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

shell_cli_parse_standard_only usage "$@" || exit 1
set -- ${SHELL_CLI_ARGS[@]+"${SHELL_CLI_ARGS[@]}"}

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would render kind kube-apiserver OIDC manifest"
  exit 0
fi

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would render kind kube-apiserver OIDC manifest"
  exit 0
fi

if [[ "$#" -eq 7 ]]; then
  set -- "$(absolute_path "$1")" "$(absolute_path "$2")" "$3" "$4" "$5" "$6" "$7"
else
  usage >&2
  printf '%s: expected 7 positional arguments\n' "$(shell_cli_script_name)" >&2
  exit 1
fi

exec go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/render-kind-apiserver-oidc-manifest "$@"
