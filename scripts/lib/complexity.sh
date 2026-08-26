#!/usr/bin/env bash
# shellcheck shell=bash
#
# Cyclomatic complexity for bash functions.
#
# McCabe's measure counts the linearly independent paths through a function:
# one for the straight line, plus one for every point the flow can branch. The
# number is a review prompt, not a verdict -- a function scoring 14 is telling
# you it holds fourteen paths a reader has to keep straight, and that a name is
# probably hiding in there.
#
# Function discovery and comment stripping are not reimplemented here.
# scripts/lib/mutation.sh already resolves function ranges and strips comments
# without being fooled by heredocs, `${var#prefix}` or a quoted hash, and a
# second parser would only drift from the first.
#
# Bash 3.2 compatible on purpose (macOS stock bash): no associative arrays,
# no mapfile, no namerefs.

# shellcheck source=scripts/lib/mutation.sh
. "${BASH_SOURCE[0]%/*}/mutation.sh"

# Branch keywords. `else` is absent deliberately: it introduces no new
# condition, it is the path an existing `if` already accounted for. `elif`
# does introduce one. `case` is counted through its arms, not its head.
_COMPLEXITY_KEYWORDS="if elif while until for"

# Count decision points on one line of shell. The line must already have had
# its comment stripped, or a `# && something` remark inflates the score.
complexity_line_points() {
  local line="$1"
  local points=0
  local keyword="" pos=""

  for keyword in ${_COMPLEXITY_KEYWORDS}; do
    for pos in $(mutation_scan_plain "${line}" "${keyword}"); do
      if mutation_word_boundary_ok "${line}" "${pos}" "${#keyword}"; then
        points=$((points + 1))
      fi
    done
  done

  # `&&` and `||` each add a path, and neither can be confused for an
  # identifier, so they need no boundary check. A single `&` or `|` is a
  # pipeline or a background job, not a branch, and `mutation_scan_plain`
  # matching the two-character needle already excludes them.
  for pos in $(mutation_scan_plain "${line}" "&&"); do
    points=$((points + 1))
  done
  for pos in $(mutation_scan_plain "${line}" "||"); do
    points=$((points + 1))
  done

  # A case arm is a branch. Match `pattern)` at the end of a line, which is
  # how every arm in this repo is written, and skip `;;`-only and `esac`
  # lines. `(pattern)` with a leading paren is the same arm, one style apart.
  if [[ "${line}" =~ ^[[:space:]]*\(?[^\(\)]+\)[[:space:]]*$ ]] &&
    [[ ! "${line}" =~ ^[[:space:]]*(esac|\;\;)[[:space:]]*$ ]]; then
    points=$((points + 1))
  fi

  printf '%s\n' "${points}"
}

# Cyclomatic complexity of the line range [start,end] of a file: one for the
# entry path, plus every decision point inside it.
complexity_score_range() {
  local file="$1"
  local start="$2"
  local end="$3"
  local score=1
  local lineno=0
  local line="" stripped=""

  while IFS= read -r line || [ -n "${line}" ]; do
    lineno=$((lineno + 1))
    if [ "${lineno}" -lt "${start}" ]; then
      continue
    fi
    if [ "${lineno}" -gt "${end}" ]; then
      break
    fi
    stripped="$(mutation_strip_comment "${line}")"
    score=$((score + $(complexity_line_points "${stripped}")))
  done <"${file}"

  printf '%s\n' "${score}"
}

# Print `name<TAB>score<TAB>start<TAB>end` for every function in a file, in
# source order.
complexity_report_file() {
  local file="$1"
  local name="" start="" end="" score=""

  mutation_list_functions "${file}" | while IFS="${_MUTATION_TAB}" read -r name start end; do
    [ -n "${name}" ] || continue
    score="$(complexity_score_range "${file}" "${start}" "${end}")"
    printf '%s\t%s\t%s\t%s\n' "${name}" "${score}" "${start}" "${end}"
  done
}
