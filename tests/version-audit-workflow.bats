#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "version audit workflow pins GitHub Actions by SHA and runs lightweight audits" {
  run uv run --isolated python - "${REPO_ROOT}/.github/workflows/version-audit.yml" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

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

assert "cron: '0 9 * * 1'" in text
assert "run: make check-version" in text
assert "run: ./terraform/kubernetes/scripts/check-provider-version.sh --execute" in text
assert "run: ./terraform/kubernetes/scripts/check-version.sh --execute --ci" in text
PY

  [ "${status}" -eq 0 ]
}
