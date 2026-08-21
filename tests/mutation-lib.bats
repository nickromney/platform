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
