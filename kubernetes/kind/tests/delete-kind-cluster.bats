#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/delete-kind-cluster.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "delete-kind-cluster retries transient exit-event failures" {
  attempts_file="${BATS_TEST_TMPDIR}/attempts"
  printf '0' >"${attempts_file}"

  cat >"${TEST_BIN}/kind" <<EOF
#!/usr/bin/env bash
set -euo pipefail
attempts_file="${attempts_file}"
count="\$(cat "\${attempts_file}")"
count="\$((count + 1))"
printf '%s' "\${count}" >"\${attempts_file}"
if [[ "\${count}" -eq 1 ]]; then
  echo 'ERROR: cannot remove container "kind-local-worker": could not kill container: tried to kill container, but did not receive an exit event' >&2
  exit 1
fi
echo 'Deleted nodes: ["kind-local-control-plane" "kind-local-worker"]'
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "ps" ]]; then
  echo -e 'kind-local-worker\tExited (137) 2 seconds ago'
fi
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}" --name kind-local --retries 3 --delay-seconds 0

  [ "${status}" -eq 0 ]
  [ "$(cat "${attempts_file}")" = "2" ]
  [[ "${output}" == *'Deleted nodes:'* ]]
}

@test "delete-kind-cluster fails fast on non-retryable errors" {
  attempts_file="${BATS_TEST_TMPDIR}/attempts"
  printf '0' >"${attempts_file}"

  cat >"${TEST_BIN}/kind" <<EOF
#!/usr/bin/env bash
set -euo pipefail
attempts_file="${attempts_file}"
count="\$(cat "\${attempts_file}")"
count="\$((count + 1))"
printf '%s' "\${count}" >"\${attempts_file}"
echo 'boom' >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}" --name kind-local --retries 3 --delay-seconds 0

  [ "${status}" -ne 0 ]
  [ "$(cat "${attempts_file}")" = "1" ]
  [[ "${output}" == *'non-retryable failure'* ]]
}
