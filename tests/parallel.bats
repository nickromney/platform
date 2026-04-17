#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export PARALLEL_LIB="${REPO_ROOT}/scripts/lib/parallel.sh"
}

@test "parallel_map_lines preserves input order" {
  run bash -lc "source '${PARALLEL_LIB}'; callback() { sleep 1; printf 'processed:%s\n' \"\$1\"; }; input='${BATS_TEST_TMPDIR}/items.txt'; out='${BATS_TEST_TMPDIR}/out'; printf 'a\nb\nc\n' >\"\${input}\"; parallel_map_lines 2 callback \"\${input}\" \"\${out}\""

  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'processed:a\nprocessed:b\nprocessed:c')" ]
}

@test "parallel_map_lines uses bounded concurrency" {
  run bash -lc "source '${PARALLEL_LIB}'; callback() { sleep 1; printf 'done:%s\n' \"\$1\"; }; input='${BATS_TEST_TMPDIR}/items.txt'; out='${BATS_TEST_TMPDIR}/out'; printf '1\n2\n3\n' >\"\${input}\"; start=\$(date +%s); parallel_map_lines 2 callback \"\${input}\" \"\${out}\" >/dev/null; elapsed=\$(( \$(date +%s) - start )); printf 'elapsed=%s\n' \"\${elapsed}\""

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ elapsed=1|elapsed=2 ]]
}
