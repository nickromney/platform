#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/apps/subnetcalc/scripts/vendor-apim-simulator.sh"
  export SOURCE_REPO="${BATS_TEST_TMPDIR}/source"
  export TARGET_DIR="${BATS_TEST_TMPDIR}/target"
  export METADATA_FILE="${BATS_TEST_TMPDIR}/apim-simulator.vendor.json"

  mkdir -p "${SOURCE_REPO}"
  git -C "${SOURCE_REPO}" init -q
  git -C "${SOURCE_REPO}" config user.name "Test User"
  git -C "${SOURCE_REPO}" config user.email "test@example.com"
  git -C "${SOURCE_REPO}" config commit.gpgSign false
  git -C "${SOURCE_REPO}" config tag.gpgSign false

  mkdir -p "${SOURCE_REPO}/app" "${SOURCE_REPO}/contracts" "${SOURCE_REPO}/docs" "${SOURCE_REPO}/examples/demo" "${SOURCE_REPO}/tests" "${SOURCE_REPO}/ui"
  cat >"${SOURCE_REPO}/app/__init__.py" <<'EOF'
__version__ = "0.1.0"
EOF
  cat >"${SOURCE_REPO}/contracts/contract_matrix.yml" <<'EOF'
contracts: []
EOF
  cat >"${SOURCE_REPO}/pyproject.toml" <<'EOF'
[project]
name = "apim-simulator"
version = "0.1.0"
EOF
  cat >"${SOURCE_REPO}/uv.lock" <<'EOF'
version = 1
EOF
  cat >"${SOURCE_REPO}/Dockerfile" <<'EOF'
FROM python:3.13
COPY --chown=${APP_UID}:${APP_GID} app ./app
COPY --chown=${APP_UID}:${APP_GID} examples ./examples
EOF
  cat >"${SOURCE_REPO}/LICENSE.md" <<'EOF'
MIT
EOF
  cat >"${SOURCE_REPO}/docs/tutorial.md" <<'EOF'
# Tutorial
EOF
  cat >"${SOURCE_REPO}/examples/demo/config.json" <<'EOF'
{}
EOF
  cat >"${SOURCE_REPO}/tests/test_demo.py" <<'EOF'
def test_demo():
    assert True
EOF
  cat >"${SOURCE_REPO}/ui/package.json" <<'EOF'
{"name":"ui"}
EOF

  git -C "${SOURCE_REPO}" add .
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
  [ -f "${TARGET_DIR}/app/__init__.py" ]
  [ -f "${TARGET_DIR}/contracts/contract_matrix.yml" ]
  [ -f "${TARGET_DIR}/pyproject.toml" ]
  [ -f "${TARGET_DIR}/uv.lock" ]
  [ -f "${TARGET_DIR}/Dockerfile" ]
  [ -f "${TARGET_DIR}/LICENSE.md" ]
  [ ! -e "${TARGET_DIR}/docs" ]
  [ ! -e "${TARGET_DIR}/examples" ]
  [ ! -e "${TARGET_DIR}/tests" ]
  [ ! -e "${TARGET_DIR}/ui" ]
  ! grep -q 'examples ./examples' "${TARGET_DIR}/Dockerfile"
  [ ! -e "${TARGET_DIR}/old.txt" ]
  [[ "${output}" == *"Vendored apim-simulator ${SOURCE_COMMIT} (tag v0.1.0, runtime profile)"* ]]
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
assert metadata["subset"]["profile"] == "runtime"
assert "app" in metadata["subset"]["included_paths"]
assert "examples/" in metadata["subset"]["excluded_paths"]
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
