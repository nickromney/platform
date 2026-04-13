#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "release workflow pins GitHub Actions by SHA" {
  run python3 - "${REPO_ROOT}/.github/workflows/release.yml" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
expected = {
    "actions/checkout": ("de0fac2e4500dabe0009e67214ff5f5447ce83dd", "v6.0.2"),
    "actions/setup-node": ("53b83947a5a98c8d113130e565377fae1a50d02f", "v6"),
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
