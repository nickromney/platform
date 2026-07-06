#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "CI workflow pins GitHub Actions and runs lint plus hermetic Bats" {
  run uv run --isolated python - "${REPO_ROOT}/.github/workflows/ci.yml" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

expected = {
    "actions/checkout": ("9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0", "v7.0.0"),
    "actions/setup-node": ("48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e", "v6.4.0"),
}

assert re.search(r"^on:\n  pull_request:\n  push:\n    branches:\n      - main\n", text, re.MULTILINE)
assert re.search(r"^permissions:\n  contents: read\n", text, re.MULTILINE)
assert "runs-on: ubuntu-latest" in text
assert "run: make lint" in text
assert "run: make test-ci" in text
assert ".devcontainer/toolchain-versions.sh" in text
assert "yamllint==1.38.0" in text
assert "markdownlint-cli2@0.22.1" in text
assert "docker run" not in text.lower()
assert "docker compose" not in text.lower()
assert "kind create" not in text

uses = re.findall(r"uses:\s*([^\s#]+)(?:\s*#\s*(v[^\s]+))?", text)
assert uses, "workflow must use pinned first-party actions"

seen = set()
for full_ref, selector in uses:
    repo, _, sha = full_ref.partition("@")
    assert repo in expected, repo
    expected_sha, expected_selector = expected[repo]
    assert re.fullmatch(r"[0-9a-f]{40}", sha), (repo, sha)
    assert sha == expected_sha, (repo, sha, expected_sha)
    assert selector == expected_selector, (repo, selector, expected_selector)
    seen.add(repo)

assert seen == set(expected), seen
PY

  [ "${status}" -eq 0 ]
}
