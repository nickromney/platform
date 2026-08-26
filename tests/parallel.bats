#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export PARALLEL_LIB="${REPO_ROOT}/scripts/lib/parallel.sh"
}

@test "parallel_map_lines preserves input order" {
  run bash -lc "source '${PARALLEL_LIB}'; callback() { sleep 1; printf 'processed:%s\n' \"\$1\"; }; input='${BATS_TEST_TMPDIR}/items.txt'; out='${BATS_TEST_TMPDIR}/out'; printf 'a\nb\nc\n' >\"\${input}\"; parallel_map_lines 2 callback \"\${input}\" \"\${out}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'processed:a\nprocessed:b\nprocessed:c')" ]
}

@test "parallel_map_lines uses bounded concurrency" {
  # 2s per item, so the landmarks are 2s apart rather than 1s: 3 items at
  # concurrency 2 means unbounded finishes near 2s, bounded near 4s and serial
  # near 6s. See tests/check-provider-version.bats for the same reasoning.
  run bash -lc "source '${PARALLEL_LIB}'; callback() { sleep 2; printf 'done:%s\n' \"\$1\"; }; input='${BATS_TEST_TMPDIR}/items.txt'; out='${BATS_TEST_TMPDIR}/out'; printf '1\n2\n3\n' >\"\${input}\"; start=\$(date +%s); parallel_map_lines 2 callback \"\${input}\" \"\${out}\" >/dev/null; elapsed=\$(( \$(date +%s) - start )); printf 'elapsed=%s\n' \"\${elapsed}\""

  [ "${status}" -eq 0 ]
  # Integer comparison: the old `elapsed=1|elapsed=2` regex was unanchored and
  # matched elapsed=10 as well.
  elapsed="$(printf '%s\n' "${output}" | sed -n 's/^elapsed=//p')"
  [ -n "${elapsed}" ]
  [ "${elapsed}" -ge 4 ]
  [ "${elapsed}" -lt 6 ]
}

@test "parallel_temp_file falls back to mktemp when the platform helper is absent" {
  # Kills LOGICAL_AND_OR at parallel.sh:12: flipped to ||, the absent-helper
  # case still enters the delegation branch, the missing helper errors, and
  # the named variable is left empty.
  run bash -lc "unset -f platform_mktemp_file; source '${PARALLEL_LIB}'; parallel_temp_file myvar; printf 'var=%s' \"\${myvar:-}\""

  [ "${status}" -eq 0 ]
  path="$(printf '%s' "${output}" | sed -n 's/^var=//p')"
  [ -n "${path}" ]
  [ -f "${path}" ]
}

@test "parallel_temp_file delegates to the platform helper when present" {
  # Kills RETURN_CODE at parallel.sh:14: the delegation branch's return status
  # is part of the contract its callers see. Captured into the output because
  # a trailing printf would otherwise mask it.
  run bash -lc "platform_mktemp_file() { printf -v \"\$1\" '%s' '${BATS_TEST_TMPDIR}/stub-path'; }; source '${PARALLEL_LIB}'; parallel_temp_file myvar; st=\$?; printf 'st=%s var=%s' \"\${st}\" \"\${myvar:-}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "st=0 var=${BATS_TEST_TMPDIR}/stub-path" ]
}

@test "parallel_wait_all reports failure when a child fails" {
  # Kills NEGATION_DROP at parallel.sh:31: without the inversion a failed
  # child is indistinguishable from a successful one.
  run bash -lc "source '${PARALLEL_LIB}'; sleep 0.2 & ok=\$!; false & bad=\$!; parallel_wait_all \"\$ok\" \"\$bad\""

  [ "${status}" -eq 1 ]
}

@test "parallel_wait_all returns zero when every child succeeds" {
  run bash -lc "source '${PARALLEL_LIB}'; true & a=\$!; true & b=\$!; parallel_wait_all \"\$a\" \"\$b\""

  [ "${status}" -eq 0 ]
}

@test "parallel_map_lines processes a final line with no trailing newline" {
  # Kills LOGICAL_AND_OR at parallel.sh:51: ANDing read's EOF status with the
  # residue check drops an unterminated last line instead of processing it.
  run bash -lc "source '${PARALLEL_LIB}'; callback() { printf 'processed:%s\n' \"\$1\"; }; input='${BATS_TEST_TMPDIR}/items.txt'; out='${BATS_TEST_TMPDIR}/out'; printf 'a\nb' >\"\${input}\"; parallel_map_lines 2 callback \"\${input}\" \"\${out}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'processed:a\nprocessed:b')" ]
}
