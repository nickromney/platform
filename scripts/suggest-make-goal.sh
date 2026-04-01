#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: suggest-make-goal.sh [--goal GOAL] [--candidate GOAL]... [--dry-run]

Suggest the closest known Make goal for an unknown goal string.

Positional compatibility:
  suggest-make-goal.sh <unknown-goal> <candidate> [candidate...]

Options:
  --goal GOAL        unknown goal to compare
  --candidate GOAL   candidate make goal (repeatable)
  --dry-run          show the comparison set and exit before scoring
  --execute          run the comparison (preferred explicit form for query workflows)
  -h, --help         show this help
EOF
}

unknown_goal=""
dry_run=0
candidate_goals=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --goal)
      shift
      [[ "$#" -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--goal" >&2; exit 1; }
      unknown_goal="$1"
      ;;
    --candidate)
      shift
      [[ "$#" -gt 0 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--candidate" >&2; exit 1; }
      candidate_goals+=("$1")
      ;;
    --dry-run)
      dry_run=1
      ;;
    --execute)
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ "$#" -gt 0 ]]; do
        candidate_goals+=("$1")
        shift
      done
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
    *)
      if [[ -z "${unknown_goal}" ]]; then
        unknown_goal="$1"
      else
        candidate_goals+=("$1")
      fi
      ;;
  esac
  shift
done

if [[ "${dry_run}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would score '${unknown_goal:-<none>}' against ${#candidate_goals[@]} candidate goal(s)"
  exit 0
fi

if [[ -z "${unknown_goal}" ]]; then
  exit 0
fi

if [[ "${#candidate_goals[@]}" -eq 0 ]]; then
  exit 0
fi

printf '%s\n' "${candidate_goals[@]}" | awk -v needle="${unknown_goal}" '
function normalize(value,   out) {
  out = tolower(value)
  gsub(/[._-]/, "", out)
  return out
}

function min3(a, b, c,   best) {
  best = (a < b) ? a : b
  return (best < c) ? best : c
}

function levenshtein(a, b,   len_a, len_b, i, j, ca, cb, cost, prev, curr) {
  len_a = length(a)
  len_b = length(b)

  if (len_a == 0) {
    return len_b
  }
  if (len_b == 0) {
    return len_a
  }

  for (j = 0; j <= len_b; j++) {
    prev[j] = j
  }

  for (i = 1; i <= len_a; i++) {
    curr[0] = i
    ca = substr(a, i, 1)
    for (j = 1; j <= len_b; j++) {
      cb = substr(b, j, 1)
      cost = (ca == cb) ? 0 : 1
      curr[j] = min3(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
    }
    for (j = 0; j <= len_b; j++) {
      prev[j] = curr[j]
    }
  }

  return prev[len_b]
}

BEGIN {
  normalized_needle = normalize(needle)
  best = ""
  best_score = -1
}

{
  candidate = $0
  normalized_candidate = normalize(candidate)
  score = levenshtein(normalized_needle, normalized_candidate)

  if (index(normalized_candidate, normalized_needle) == 1 || index(normalized_needle, normalized_candidate) == 1) {
    score--
  }

  if (best == "" || score < best_score || (score == best_score && length(candidate) < length(best))) {
    best = candidate
    best_score = score
  }
}

END {
  threshold = (length(normalized_needle) <= 4) ? 2 : 3
  if (best != "" && best_score <= threshold) {
    printf "Did you mean '\''%s'\''?", best
  }
}
'
