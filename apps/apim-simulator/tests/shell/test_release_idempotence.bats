#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

  export RELEASE_VERSION
  RELEASE_VERSION="$(
    uv run --project "$REPO_ROOT" python - <<'PY'
import tomllib
from pathlib import Path

print(tomllib.loads(Path("pyproject.toml").read_text(encoding="utf-8"))["project"]["version"])
PY
  )"

  export RELEASE_TAG="v${RELEASE_VERSION}"
  TAG_CREATED=0
}

teardown() {
  if [[ "${TAG_CREATED:-0}" -eq 1 ]]; then
    git -C "$REPO_ROOT" tag -d "$RELEASE_TAG" >/dev/null 2>&1 || true
  fi
}

ensure_release_tag() {
  if ! git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
    git -C "$REPO_ROOT" tag -a "$RELEASE_TAG" -m "Release ${RELEASE_TAG}"
    TAG_CREATED=1
  fi
}

@test "make release is idempotent when the version is already current" {
  ensure_release_tag

  run make -C "$REPO_ROOT" release VERSION="$RELEASE_VERSION"

  [ "$status" -eq 0 ]
  [[ "$output" == *"release ${RELEASE_VERSION} is already complete"* ]]
}

@test "make release-tag is idempotent when the tag already exists" {
  ensure_release_tag

  run make -C "$REPO_ROOT" release-tag VERSION="$RELEASE_VERSION"

  [ "$status" -eq 0 ]
  [[ "$output" == *"tag ${RELEASE_TAG} already exists; release is already complete"* ]]
}
