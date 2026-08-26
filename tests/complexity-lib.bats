#!/usr/bin/env bash
#
# Oracle for scripts/lib/complexity.sh.
#
# Status is asserted on every call, not just output. The mutation baseline for
# this repo kept finding that suites execute a function's early returns without
# ever checking what they returned, so `run` plus a bare output comparison
# leaves RETURN_CODE flips alive.

setup() {
  local root
  root="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)"
  export LIB="${root}/scripts/lib/complexity.sh"
}

points() {
  run bash -c "source '${LIB}'; complexity_line_points '$1'"
}

blanked() {
  run bash -c "source '${LIB}'; complexity_blank_quoted '$1'; printf '%s' \"\${COMPLEXITY_BLANKED}\""
}

@test "a line with no branching scores nothing" {
  points 'printf %s "${x}"'

  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "each branch keyword counts once" {
  points 'if true; then'
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  points 'elif true; then'
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  points 'while true; do'
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  points 'until false; do'
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  points 'for i in a b; do'
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "else adds no path because its condition was already counted" {
  # McCabe counts conditions, not blocks. An `if`/`else` pair is two paths from
  # one decision, and that decision was counted at the `if`. Counting `else`
  # too would inflate every two-armed conditional in the repo by one.
  points 'else'

  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "keywords glued into identifiers are not branches" {
  # The boundary check is the whole reason this reuses mutation.sh's scanner.
  # `ifconfig` starts with `if` and `format` contains `for`; neither branches.
  points 'ifconfig eth0'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  points 'format_output "${x}"'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  points 'local uniform=1'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "logical operators each add a path" {
  points 'a && b || c'

  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}

@test "a single pipe or ampersand is not a branch" {
  # A pipeline and a background job are not decisions. Only the doubled forms
  # are, which is why the needle is two characters wide.
  points 'sort | uniq'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  points 'worker &'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "a case arm counts as a branch but esac and ;; do not" {
  points '  pattern)'
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]

  points '  esac'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  points '  ;;'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "blanking hides quoted content but keeps the quotes and the length" {
  # Length is preserved so a caller can still reason about offsets, and the
  # quote characters survive so a quoted case arm still reads as an arm.
  blanked 'echo "a && b"'

  [ "${status}" -eq 0 ]
  [ "${output}" = 'echo "      "' ]
  [ "${#output}" -eq 13 ]
}

@test "the public entry point blanks for you; the private counter does not" {
  # This is the contract, pinned rather than described in a comment. Calling
  # the raw counter on unblanked source returns a plausible number instead of
  # an error -- 1 here, from an operator that is inside quotes and branches
  # nothing. That is precisely why the raw counter is private and this public
  # one blanks first. If someone later makes complexity_line_points stop
  # blanking, this fails rather than quietly inflating every score in the repo.
  points 'echo "a && b"'
  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]

  run bash -c "source '${LIB}'; _complexity_count_points 'echo \"a && b\"'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "quote state carries from one line to the next" {
  # The defect this library was fixed for: an awk program opens on one line and
  # its `for` sits several lines later, where nothing on the line itself shows
  # it is quoted.
  #
  # Uses the private counter deliberately. The public entry point blanks its
  # own argument, which would re-enter the quote scanner and overwrite the very
  # state under test -- the hazard that split these two functions apart.
  run bash -c "
    source '${LIB}'
    complexity_blank_quoted \"awk '\"
    complexity_blank_quoted '  for (i = 0; i < 3; i++) {'
    _complexity_count_points \"\${COMPLEXITY_BLANKED}\"
  "

  [ "${status}" -eq 0 ]
  [ "${output}" = "0" ]
}

@test "a closing quote returns the scanner to shell" {
  # The mirror of the test above: without it, a suite could pass by treating
  # everything after the first quote as forever-quoted.
  run bash -c "
    source '${LIB}'
    complexity_blank_quoted \"awk 'program'\"
    complexity_blank_quoted 'if true; then'
    _complexity_count_points \"\${COMPLEXITY_BLANKED}\"
  "

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "score_range starts at one for a function with no branches" {
  # The entry path itself is a path. A branchless function scores 1, not 0.
  cat >"${BATS_TEST_TMPDIR}/f.sh" <<'EOF'
plain() {
  printf 'hi\n'
}
EOF

  run bash -c "source '${LIB}'; complexity_score_range '${BATS_TEST_TMPDIR}/f.sh' 1 3"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "score_range counts only lines inside the range" {
  # Guards the boundary comparisons: a mutant that runs one line early or late
  # picks up the neighbouring `if` and scores 2.
  cat >"${BATS_TEST_TMPDIR}/g.sh" <<'EOF'
if outside; then :; fi
target() {
  printf 'hi\n'
}
if alsooutside; then :; fi
EOF

  run bash -c "source '${LIB}'; complexity_score_range '${BATS_TEST_TMPDIR}/g.sh' 2 4"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "a multi-line embedded awk program contributes nothing" {
  # The regression this library exists to avoid: semver_sort_key scored 2 on an
  # awk `for`. Written as a range so the carried quote state is what is proved.
  cat >"${BATS_TEST_TMPDIR}/h.sh" <<'EOF'
embedded() {
  awk '
    BEGIN {
      for (i = 1; i <= 6; i++) {
        if (i > 2 || i < 0) print i
      }
    }
  '
}
EOF

  run bash -c "source '${LIB}'; complexity_score_range '${BATS_TEST_TMPDIR}/h.sh' 1 9"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "a comment cannot inflate a score" {
  cat >"${BATS_TEST_TMPDIR}/i.sh" <<'EOF'
commented() {
  # if this counted && so would this
  printf 'hi\n'
}
EOF

  run bash -c "source '${LIB}'; complexity_score_range '${BATS_TEST_TMPDIR}/i.sh' 1 4"

  [ "${status}" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "report_file emits name score and range for every function in order" {
  cat >"${BATS_TEST_TMPDIR}/j.sh" <<'EOF'
first() {
  printf 'a\n'
}

second() {
  if true && false; then
    printf 'b\n'
  fi
}
EOF

  run bash -c "source '${LIB}'; complexity_report_file '${BATS_TEST_TMPDIR}/j.sh'"

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'first\t1\t1\t3')" ]
  [ "${lines[1]}" = "$(printf 'second\t3\t5\t9')" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "an unterminated quote does not grow the blanked line" {
  # Kills BOUNDARY_CHECK at complexity.sh:54. Under `-le` the scan runs one
  # extra pass at i == len. With the scanner outside a quote that pass appends
  # nothing and reads as equivalent -- but inside an unterminated quote it
  # appends a blank, silently lengthening the line. An awk program opened on
  # one line is exactly that case, so this is the common path, not an exotic
  # one. Length is the assertion because the added character is a space.
  # Not via the `blanked` helper: it wraps its argument in single quotes, and
  # the fixture here is a lone single quote.
  run bash -c "source '${LIB}'; complexity_blank_quoted \"awk '\"; printf '%s' \"\${COMPLEXITY_BLANKED}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "awk '" ]
  [ "${#output}" -eq 5 ]
}

@test "score_range counts a decision on the first line of the range" {
  # Kills BOUNDARY_CHECK at complexity.sh:141. Under `-le` the skip runs one
  # line too far and swallows the opening line. Every earlier range test opens
  # on a `name() {` line that carries no decision, so the mutant survived them
  # all; this one puts the branch on the first line itself.
  cat >"${BATS_TEST_TMPDIR}/k.sh" <<'EOF'
if leading; then
  printf 'x\n'
fi
EOF

  run bash -c "source '${LIB}'; complexity_score_range '${BATS_TEST_TMPDIR}/k.sh' 1 3"

  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}

@test "score_range counts a decision on the last line of the range" {
  # Kills BOUNDARY_CHECK at complexity.sh:144. Under `-ge` the loop breaks one
  # line early and drops the closing line. The earlier tests all end on a bare
  # `}`, which carries no decision and so hides the mutant.
  cat >"${BATS_TEST_TMPDIR}/l.sh" <<'EOF'
trailing() {
  a && b
}
EOF

  run bash -c "source '${LIB}'; complexity_score_range '${BATS_TEST_TMPDIR}/l.sh' 1 2"

  [ "${status}" -eq 0 ]
  [ "${output}" = "2" ]
}
