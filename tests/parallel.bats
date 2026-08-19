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
