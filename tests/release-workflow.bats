#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export RELEASE_VERSION
  RELEASE_VERSION="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"
  export TAG_TEST_VERSION="9.9.9"
  export TAG_TEST_NAME="v${TAG_TEST_VERSION}"
  export TAG_TEST_VERSION_FILE="${BATS_TEST_TMPDIR}/VERSION"
  printf '%s\n' "${TAG_TEST_VERSION}" >"${TAG_TEST_VERSION_FILE}"
}

teardown() {
  git -C "${REPO_ROOT}" tag -d "${TAG_TEST_NAME}" >/dev/null 2>&1 || true
}

@test "release workflow pins GitHub Actions by SHA" {
  run uv run --isolated python - "${REPO_ROOT}/.github/workflows/release.yml" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
expected = {
    "actions/checkout": ("de0fac2e4500dabe0009e67214ff5f5447ce83dd", "v6.0.2"),
    "actions/setup-node": ("48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e", "v6.4.0"),
}

for repo, (sha, selector) in expected.items():
    match = re.search(
        rf"uses:\s*{re.escape(repo)}@([0-9a-f]{{40}})(?:\s*#\s*(v[^\s]+))?",
        text,
    )
    assert match, repo
    assert match.group(1) == sha, (repo, match.group(1), sha)
    assert match.group(2) == selector, (repo, match.group(2), selector)
PY

  [ "${status}" -eq 0 ]
}

@test "make release is idempotent when the version is already prepared" {
  run make -C "${REPO_ROOT}" release VERSION="${RELEASE_VERSION}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"release ${RELEASE_VERSION} is already prepared"* || "${output}" == *"release ${RELEASE_VERSION} is already complete"* ]]
}

@test "make release-tag is idempotent when the tag already exists" {
  git -C "${REPO_ROOT}" -c tag.gpgSign=false tag -a "${TAG_TEST_NAME}" -m "Release ${TAG_TEST_NAME}"

  run make -C "${REPO_ROOT}" release-tag VERSION="${TAG_TEST_VERSION}" VERSION_FILE="${TAG_TEST_VERSION_FILE}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"tag ${TAG_TEST_NAME} already exists; release is already complete"* ]]
}
