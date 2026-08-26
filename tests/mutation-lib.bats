#!/usr/bin/env bash

setup() {
  local root
  root="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)"
  export LIB="${root}/scripts/lib/mutation.sh"
}

@test "strip_comment truncates at an unquoted word-boundary hash" {
  run bash -c "source '${LIB}'; mutation_strip_comment 'echo hi # note'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "echo hi " ]
}

@test "strip_comment keeps hashes inside expansions quotes and shebangs" {
  run bash -c "source '${LIB}'; mutation_strip_comment 'local x=\${y#pre}'"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'local x=${y#pre}' ]

  run bash -c "source '${LIB}'; mutation_strip_comment 'echo \"# not a comment\"'"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'echo "# not a comment"' ]

  run bash -c "source '${LIB}'; mutation_strip_comment '#!/usr/bin/env bash'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "scan_plain reports every offset left to right" {
  run bash -c "source '${LIB}'; mutation_scan_plain 'a&&b&&c' '&&'"

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "1" ]
  [ "${lines[1]}" = "4" ]
  [ "${#lines[@]}" = "2" ]
}

@test "generate_line_mutants flips comparisons logicals and return codes" {
  local out
  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants '[ \"\${a}\" -eq 1 ] && return 0'")"

  printf '%s\n' "${out}" | grep -Fq $'NUMERIC_COMPARE\t[ "${a}" -ne 1 ] && return 0'
  printf '%s\n' "${out}" | grep -Fq $'LOGICAL_AND_OR\t[ "${a}" -eq 1 ] || return 0'
  printf '%s\n' "${out}" | grep -Fq $'RETURN_CODE\t[ "${a}" -eq 1 ] && return 1'

  if printf '%s\n' "${out}" | grep -q -- '-lt'; then
    fail "unexpected BOUNDARY_CHECK mutant on a line without boundary ops"
  fi
}

@test "boolean literal swaps respect word boundaries" {
  local out
  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants 'use_cache=true'")"
  printf '%s\n' "${out}" | grep -Fq $'BOOLEAN_LITERAL\tuse_cache=false'

  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants 'local vtrue=1'")"
  if printf '%s\n' "${out}" | grep -q 'vfalse'; then
    fail "mutated inside an identifier"
  fi
}

@test "negation drop removes only standalone bang tokens" {
  local out
  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants 'if ! grep -q x f; then'")"
  printf '%s\n' "${out}" | grep -Fq $'NEGATION_DROP\tif  grep -q x f; then'

  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants '[ \"\${a}\" != \"\${b}\" ]'")"
  if printf '%s\n' "${out}" | grep -q 'NEGATION_DROP'; then
    fail "treated != as a negation site"
  fi
}

@test "heredoc_tag extracts tag and dash form" {
  run bash -c "source '${LIB}'; mutation_heredoc_tag \"cat <<'EOF'\""

  [ "${status}" -eq 0 ]
  [ "${output}" = $'EOF\tnodash' ]

  run bash -c "source '${LIB}'; mutation_heredoc_tag 'cat <<-EOF'"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'EOF\tdash' ]

  run bash -c "source '${LIB}'; mutation_heredoc_tag 'curl <<<\"\${x}\"'"

  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "list_functions maps ranges and ignores braces inside heredocs" {
  local fixture="${BATS_TMPDIR}/mutation-fn-fixture.sh"
  cat >"${fixture}" <<'FIX'
top_level=1
first() {
  cat <<'EOF'
} not a close
EOF
  return 0
}

second() {
  [ 1 -eq 1 ]
}
FIX

  run bash -c "source '${LIB}'; mutation_list_functions '${fixture}'"

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = $'first\t2\t7' ]
  [ "${lines[1]}" = $'second\t9\t11' ]
}

@test "scan_plain reports success on an empty needle and on an exhausted haystack" {
  # Kills RETURN_CODE at mutation.sh:73 (nothing to search for) and :76 (the
  # scan ran off the end of the haystack). Both mean "nothing more to find",
  # which every caller reads as success. Flipped to `return 1` a finished scan
  # becomes a failed one, and mutation_heredoc_tag bails on the first line that
  # has no `<<` on it.
  run bash -c "source '${LIB}'; mutation_scan_plain 'abc' ''; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]

  # 'a&&' ends on its only match, so the next pass sees an empty remainder and
  # leaves through :76 rather than through the no-further-match exit.
  run bash -c "source '${LIB}'; mutation_scan_plain 'a&&' '&&'; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "1" ]
  [ "${lines[1]}" = "st=0" ]
}

@test "boolean literal swaps fire on a token in the first column" {
  # Kills BOUNDARY_CHECK at mutation.sh:93. At offset 0 there is no preceding
  # character to inspect, which is why the guard is `-gt 0`. Under `-ge 0` the
  # lookup becomes ${hay:-1:1} -- the `:-` default form, not a negative offset
  # -- so `before` comes back as the whole haystack, and every line whose first
  # token is a mutation site silently stops being mutated.
  local out
  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants 'true && ok'")"

  printf '%s\n' "${out}" | grep -Fq $'BOOLEAN_LITERAL\tfalse && ok'
}

@test "boolean literal swaps skip a token glued to a following word character" {
  # Kills RETURN_CODE at mutation.sh:101, the trailing half of the word-boundary
  # check. Without it `trueish` matches `true` at a word start and is rewritten
  # to `falseish`, which is the identifier corruption the boundary rule exists
  # to prevent. The existing boundary test only covers the leading side.
  #
  # The fixture has to actually contain `true`: an earlier version of this test
  # used `truthy`, which is t-r-u-t-h-y and holds no `true` substring at all, so
  # it asserted nothing and the mutant survived it.
  local out
  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants 'trueish=1'")"

  if printf '%s\n' "${out}" | grep -q 'false'; then
    fail "mutated true inside the identifier trueish"
  fi
}

@test "emit_swaps reports success on an empty needle" {
  # Kills RETURN_CODE at mutation.sh:118. mutation_generate_line_mutants calls
  # emit_swaps sixteen times in a row and checks none of their statuses, so a
  # nonzero return is invisible there and only shows up in a caller that does.
  run bash -c "source '${LIB}'; MUTATION_RECORDS=''; mutation_emit_swaps 'a&&b' '' '||' LOGICAL_AND_OR plain; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]
}

@test "emit_swaps reports success from both loop exits" {
  # Kills RETURN_CODE at mutation.sh:121 and :124 -- the two ways the scan ends.
  # 'a&&' stops because the line ended on the match and the remainder is empty;
  # 'a&&b' stops because the trailing text holds no further match.
  run bash -c "source '${LIB}'; MUTATION_RECORDS=''; mutation_emit_swaps 'a&&' '&&' '||' LOGICAL_AND_OR plain; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]

  run bash -c "source '${LIB}'; MUTATION_RECORDS=''; mutation_emit_swaps 'a&&b' '&&' '||' LOGICAL_AND_OR plain; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]
}

@test "negation drop fires on a bang in the first column" {
  # Kills BOUNDARY_CHECK at mutation.sh:157, the negation-drop copy of the
  # offset-zero guard covered at :93. A line that opens with `!` has no
  # preceding character, and under `-ge 0` the ${line:-1:1} lookup returns the
  # whole line, fails the "preceded by whitespace" test, and drops the site.
  local out
  out="$(bash -c "source '${LIB}'; mutation_generate_line_mutants '! grep -q x f'")"

  printf '%s\n' "${out}" | grep -Fq $'NEGATION_DROP\t grep -q x f'
}

@test "emit_negation_drops reports success from both loop exits" {
  # Kills RETURN_CODE at mutation.sh:149 and :152. 'foo !' ends on the bang so
  # the remainder is empty; '! foo' has trailing text holding no further bang.
  run bash -c "source '${LIB}'; MUTATION_RECORDS=''; mutation_emit_negation_drops 'foo !'; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]

  run bash -c "source '${LIB}'; MUTATION_RECORDS=''; mutation_emit_negation_drops '! foo'; printf 'st=%s' \"\$?\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0" ]
}
