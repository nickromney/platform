#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/docker-prune-estimate.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "docker-prune-estimate reports the exact two-command reclaimable total" {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "system" && "${2:-}" == "df" ]]; then
  cat <<'OUT'
{"Active":"12","Reclaimable":"41.96GB (30%)","Size":"139.4GB","TotalCount":"316","Type":"Images"}
{"Active":"4","Reclaimable":"2.171GB (90%)","Size":"2.4GB","TotalCount":"21","Type":"Containers"}
{"Active":"9","Reclaimable":"13.6GB (44%)","Size":"30.83GB","TotalCount":"69","Type":"Local Volumes"}
{"Active":"0","Reclaimable":"21.26GB","Size":"43.64GB","TotalCount":"862","Type":"Build Cache"}
OUT
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/docker"

  run "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker builder prune -af : 21.26 GB"* ]]
  [[ "${output}" == *"docker system prune -af  : 44.13 GB"* ]]
  [[ "${output}" == *"combined sequence        : 65.39 GB plus any unused networks"* ]]
  [[ "${output}" == *"local volumes            : 13.6GB"* ]]
}
