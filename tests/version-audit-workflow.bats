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
    "actions/checkout": ("3d3c42e5aac5ba805825da76410c181273ba90b1", "v7.0.1"),
    "actions/setup-node": ("820762786026740c76f36085b0efc47a31fe5020", "v7.0.0"),
    "astral-sh/setup-uv": ("ae62891fec2bb8e7d6c99fc78c9fec3a63790f8d", "v10.0.0"),
}

for repo, (sha, selector) in expected.items():
    match = re.search(
        rf"uses:\s*{re.escape(repo)}@([0-9a-f]{{40}})(?:\s*#\s*(v[^\s]+))?",
        text,
    )
    assert match, repo
    assert match.group(1) == sha, (repo, match.group(1), sha)
    assert match.group(2) == selector, (repo, match.group(2), selector)

# Every action must be accounted for, not just the ones listed above. Checking
# only the known set lets an unpinned action be added without failing anything,
# which matters most in the workflow that audits supply-chain versions.
uses = re.findall(r"uses:\s*([^\s#]+)(?:\s*#\s*(v[^\s]+))?", text)
assert uses, "workflow must use pinned first-party actions"
assert {ref.partition("@")[0] for ref, _ in uses} == set(expected)

# The audit needs uv for the repo guard and helm for the component guard, and
# both versions come from the files that already own them rather than being
# restated here. Installing neither is why every scheduled run failed in 8-17s.
assert "astral-sh/uv:([^ ]+)" in text
assert "DEVCONTAINER_ARKADE_TOOLS" in text
assert "cron: '0 9 * * 1'" in text
assert "run: make check-version" in text
assert "run: ./terraform/kubernetes/scripts/check-provider-version.sh --execute" in text
assert "run: ./terraform/kubernetes/scripts/check-component-version.sh --execute --ci" in text
PY

  [ "${status}" -eq 0 ]
}
