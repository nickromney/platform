#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/apps/subnet-calculator/scripts/vendor-apim-simulator.sh"
  export SOURCE_REPO="${BATS_TEST_TMPDIR}/source"
  export TARGET_DIR="${BATS_TEST_TMPDIR}/target"
  export METADATA_FILE="${BATS_TEST_TMPDIR}/apim-simulator.vendor.json"

  mkdir -p "${SOURCE_REPO}"
  git -C "${SOURCE_REPO}" init -q
  git -C "${SOURCE_REPO}" config user.name "Test User"
  git -C "${SOURCE_REPO}" config user.email "test@example.com"

  cat >"${SOURCE_REPO}/README.md" <<'EOF'
# Test APIM Simulator
EOF

  git -C "${SOURCE_REPO}" add README.md
  git -C "${SOURCE_REPO}" commit -qm "Initial import"
  git -C "${SOURCE_REPO}" tag v0.1.0
  export SOURCE_COMMIT
  SOURCE_COMMIT="$(git -C "${SOURCE_REPO}" rev-parse HEAD)"
}

@test "vendor-apim-simulator syncs a tagged source tree and records metadata" {
  mkdir -p "${TARGET_DIR}"
  printf 'stale\n' >"${TARGET_DIR}/old.txt"

  run "${SCRIPT}" \
    --source "${SOURCE_REPO}" \
    --ref v0.1.0 \
    --target "${TARGET_DIR}" \
    --metadata "${METADATA_FILE}" \
    --execute

  [ "${status}" -eq 0 ]
  [ -f "${TARGET_DIR}/README.md" ]
  [ ! -e "${TARGET_DIR}/old.txt" ]
  [[ "${output}" == *"Vendored apim-simulator ${SOURCE_COMMIT} (tag v0.1.0)"* ]]
  [[ "${output}" == *"Recorded vendoring metadata in ${METADATA_FILE}"* ]]

  run python3 - "${METADATA_FILE}" "${SOURCE_COMMIT}" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert metadata["vendored_path"] == str(Path(sys.argv[1]).with_name("target"))
assert metadata["upstream"]["ref_kind"] == "tag"
assert metadata["upstream"]["requested_ref"] == "v0.1.0"
assert metadata["upstream"]["resolved_commit"] == sys.argv[2]
PY

  [ "${status}" -eq 0 ]
}

@test "vendor-apim-simulator rejects floating refs" {
  run "${SCRIPT}" \
    --source "${SOURCE_REPO}" \
    --ref HEAD \
    --target "${TARGET_DIR}" \
    --metadata "${METADATA_FILE}" \
    --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"--ref must be a tag or commit SHA"* ]]
}
