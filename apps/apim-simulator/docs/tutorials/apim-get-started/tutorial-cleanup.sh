#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DOCKER_BIN="${DOCKER_BIN:-docker}"
DRY_RUN=0
EXECUTE=0
# shellcheck source=../../../scripts/stack-env.sh
source "$ROOT_DIR/scripts/stack-env.sh"
stack_env_init

if [[ -n "${STACK_INSTANCE_SUFFIX:-}" ]]; then
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-apim-simulator-tutorial-${STACK_INSTANCE_SUFFIX}}"
  export COMPOSE_PROJECT_NAME
fi

usage() {
  cat <<EOF
Usage: ./docs/tutorials/apim-get-started/tutorial-cleanup.sh [--dry-run] [--execute]

Stops the tutorial Docker compose stacks and removes orphaned containers.

Options:
  --dry-run     Show this help and preview the cleanup without side effects.
  --execute     Stop the tutorial compose stacks.
  --help, -h    Show this help text.

Environment overrides:
  DOCKER_BIN    Docker CLI binary. Default: $DOCKER_BIN
EOF
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --execute)
      EXECUTE=1
      ;;
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
  shift
done

COMPOSE_FILES=(
  "$ROOT_DIR/compose.yml"
  "$ROOT_DIR/compose.public.yml"
  "$ROOT_DIR/compose.otel.yml"
  "$ROOT_DIR/compose.ui.yml"
)

if [[ "$DRY_RUN" -eq 1 || "$EXECUTE" -ne 1 ]]; then
  usage
  echo "INFO dry-run: would stop tutorial compose stacks with docker compose down --remove-orphans"
  exit 0
fi

echo "Stopping all tutorial stack variants with docker compose"
echo "Compose files:"
for compose_file in "${COMPOSE_FILES[@]}"; do
  echo "  - $(stack_env_display_path "$compose_file")"
done
echo "Running:"
echo "  $DOCKER_BIN compose \\"
for compose_file in "${COMPOSE_FILES[@]}"; do
  echo "    -f $(stack_env_display_path "$compose_file") \\"
done
echo "    down --remove-orphans"

"$DOCKER_BIN" compose \
  -f "${COMPOSE_FILES[0]}" \
  -f "${COMPOSE_FILES[1]}" \
  -f "${COMPOSE_FILES[2]}" \
  -f "${COMPOSE_FILES[3]}" \
  down --remove-orphans
