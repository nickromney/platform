#!/usr/bin/env bash
# Preserve unrelated running containers across a verification lifecycle.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/../../../scripts/lib/shell-cli.sh"
usage() {
  shell_cli_usage_line ' [--dry-run] [--execute] capture|assert SNAPSHOT'
  echo 'Capture running container identities or assert they have not changed.'
  shell_cli_standard_options
}
shell_cli_parse_standard_only usage "$@" || exit 2
shell_cli_maybe_execute_or_preview_summary usage 'would capture or assert unrelated running container identities in SNAPSHOT'
[ "$SHELL_CLI_ARG_COUNT" = 2 ] || { usage >&2; exit 2; }
set -- "${SHELL_CLI_ARGS[@]}"
case "$1" in
  capture)
    [ "$#" = 2 ] || exit 2
    ids=$(docker ps --no-trunc --quiet)
    : > "$2"
    for id in $ids; do
      docker inspect --format '{{.Id}} {{.State.Running}} {{.State.StartedAt}}' "$id" >> "$2"
    done
    ;;
  assert)
    [ "$#" = 2 ] && [ -f "$2" ] || exit 2
    while IFS= read -r expected; do
      id=${expected%% *}
      actual=$(docker inspect --format '{{.Id}} {{.State.Running}} {{.State.StartedAt}}' "$id") || {
        echo "Unrelated container disappeared: $id" >&2; exit 1;
      }
      [ "$actual" = "$expected" ] || {
        echo "Unrelated container changed liveness or restarted: $id" >&2; exit 1;
      }
    done < "$2"
    echo 'Unrelated running container identities and start times preserved'
    ;;
  *) shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"; exit 2 ;;
esac
