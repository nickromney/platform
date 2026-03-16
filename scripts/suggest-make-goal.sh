#!/usr/bin/env bash
set -euo pipefail

unknown_goal="${1:-}"
if [ -z "${unknown_goal}" ]; then
  exit 0
fi

shift || true
if [ "$#" -eq 0 ]; then
  exit 0
fi

printf '%s\n' "$@" | awk -v needle="${unknown_goal}" '
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
