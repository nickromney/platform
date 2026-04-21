#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "dependabot updates GitHub Actions weekly with a seven day cooldown" {
  run python3 - "${REPO_ROOT}/.github/dependabot.yml" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

assert re.search(r"^version:\s*2\s*$", text, re.MULTILINE)
assert re.search(r"package-ecosystem:\s*github-actions", text)
assert re.search(r"directory:\s*/\s*$", text, re.MULTILINE)
assert re.search(r"interval:\s*weekly", text)
assert re.search(r"day:\s*monday", text)
assert re.search(r'time:\s*"09:00"', text)
assert re.search(r"timezone:\s*Europe/London", text)
assert re.search(r"default-days:\s*7", text)
PY

  [ "${status}" -eq 0 ]
}
