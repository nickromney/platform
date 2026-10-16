#!/usr/bin/env bash
# Preserve unrelated running containers across a verification lifecycle.
set -euo pipefail
case "${1:-}" in
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
  *) echo 'runtime-snapshot.sh capture|assert SNAPSHOT' >&2; exit 2 ;;
esac
