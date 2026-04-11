#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DOCKER_BIN="${DOCKER_BIN:-docker}"

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial-cleanup.sh [--help]

Stops the tutorial Docker compose stacks and removes orphaned containers.

Environment overrides:
  DOCKER_BIN    Docker CLI binary. Default: $DOCKER_BIN
EOF
}

if (($# > 0)); then
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

COMPOSE_FILES=(
  "$ROOT_DIR/compose.yml"
  "$ROOT_DIR/compose.public.yml"
  "$ROOT_DIR/compose.otel.yml"
  "$ROOT_DIR/compose.ui.yml"
)

echo "Stopping all tutorial stack variants with docker compose"
echo "Compose files:"
for compose_file in "${COMPOSE_FILES[@]}"; do
  echo "  - $compose_file"
done
echo "Running:"
echo "  $DOCKER_BIN compose \\"
for compose_file in "${COMPOSE_FILES[@]}"; do
  echo "    -f $compose_file \\"
done
echo "    down --remove-orphans"

"$DOCKER_BIN" compose \
  -f "${COMPOSE_FILES[0]}" \
  -f "${COMPOSE_FILES[1]}" \
  -f "${COMPOSE_FILES[2]}" \
  -f "${COMPOSE_FILES[3]}" \
  down --remove-orphans
