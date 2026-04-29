#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/shell-cli.sh"

TUTORIAL_DIR="${TUTORIAL_DIR:-$ROOT_DIR/docs/tutorials/apim-get-started}"
TUTORIAL_CLEANUP="${TUTORIAL_CLEANUP:-$TUTORIAL_DIR/tutorial-cleanup.sh}"
APIM_HEALTH_ATTEMPTS="${APIM_HEALTH_ATTEMPTS:-60}"
APIM_HEALTH_DELAY_SECONDS="${APIM_HEALTH_DELAY_SECONDS:-1}"

usage() {
  cat <<EOF
Usage: ./scripts/run_tutorial_smoke.sh [--dry-run] [--execute] [tutorialNN ...]

Runs the mirrored APIM tutorial scripts against the live local stacks.

Without arguments, runs every numbered tutorial script in order.

Options:
  --dry-run  Show the tutorial sequence and exit before running scripts
  --execute  Run the tutorial sequence
  -h, --help Show this message

Environment overrides:
  TUTORIAL_DIR                 Tutorial directory. Default: $TUTORIAL_DIR
  TUTORIAL_CLEANUP             Cleanup script path. Default: $TUTORIAL_CLEANUP
  APIM_HEALTH_ATTEMPTS         Shared retry count for tutorial scripts. Default: $APIM_HEALTH_ATTEMPTS
  APIM_HEALTH_DELAY_SECONDS    Shared retry delay for tutorial scripts. Default: $APIM_HEALTH_DELAY_SECONDS
EOF
}

cleanup() {
  "$TUTORIAL_CLEANUP" --execute >/dev/null 2>&1 || true
}

discover_tutorials() {
  find "$TUTORIAL_DIR" -maxdepth 1 -type f -name 'tutorial[0-9][0-9].sh' | sort
}

resolve_requested_tutorials() {
  local requested
  for requested in "$@"; do
    if [[ "$requested" =~ ^[0-9]{2}$ ]]; then
      printf '%s/tutorial%s.sh\n' "$TUTORIAL_DIR" "$requested"
      continue
    fi
    if [[ "$requested" =~ ^tutorial[0-9]{2}$ ]]; then
      printf '%s/%s.sh\n' "$TUTORIAL_DIR" "$requested"
      continue
    fi
    if [[ "$requested" =~ /tutorial[0-9]{2}\.sh$ ]]; then
      printf '%s\n' "$requested"
      continue
    fi
    echo "Unknown tutorial selector: $requested" >&2
    exit 2
  done
}

run_one() {
  local tutorial_script="$1"
  local tutorial_name
  tutorial_name="$(basename "$tutorial_script")"

  if [[ ! -x "$tutorial_script" ]]; then
    echo "Tutorial script is not executable: $tutorial_script" >&2
    exit 1
  fi

  echo
  echo "==> $tutorial_name --setup"
  APIM_HEALTH_ATTEMPTS="$APIM_HEALTH_ATTEMPTS" \
  APIM_HEALTH_DELAY_SECONDS="$APIM_HEALTH_DELAY_SECONDS" \
    "$tutorial_script" --setup

  echo
  echo "==> $tutorial_name --verify"
  APIM_HEALTH_ATTEMPTS="$APIM_HEALTH_ATTEMPTS" \
  APIM_HEALTH_DELAY_SECONDS="$APIM_HEALTH_DELAY_SECONDS" \
    "$tutorial_script" --verify
}

main() {
  local -a tutorials
  local -a requested
  local tutorial_script

  shell_cli_init_standard_flags
  requested=()
  while [[ $# -gt 0 ]]; do
    if shell_cli_handle_standard_flag usage "$1"; then
      shift
      continue
    fi

    case "$1" in
      --)
        shift
        requested+=("$@")
        break
        ;;
      -*)
        shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
        usage >&2
        exit 1
        ;;
      *)
        requested+=("$1")
        shift
        ;;
    esac
  done

  tutorials=()
  if ((${#requested[@]} == 0)); then
    while IFS= read -r tutorial_script; do
      [[ -n "$tutorial_script" ]] && tutorials+=("$tutorial_script")
    done < <(discover_tutorials)
  else
    while IFS= read -r tutorial_script; do
      [[ -n "$tutorial_script" ]] && tutorials+=("$tutorial_script")
    done < <(resolve_requested_tutorials "${requested[@]}")
  fi

  if ((${#tutorials[@]} == 0)); then
    echo "No tutorial scripts found under $TUTORIAL_DIR" >&2
    exit 1
  fi

  echo "Running live tutorial smoke sequence"
  printf 'Tutorials:\n'
  for tutorial_script in "${tutorials[@]}"; do
    printf '  - %s\n' "$tutorial_script"
  done

  if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 || "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
    usage
    echo "INFO dry-run: would run each tutorial with --setup and --verify"
    exit 0
  fi

  trap cleanup EXIT

  for tutorial_script in "${tutorials[@]}"; do
    cleanup
    run_one "$tutorial_script"
  done

  echo
  echo "Live tutorial smoke passed"
}

main "$@"
