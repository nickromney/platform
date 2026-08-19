#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "CI workflow pins GitHub Actions and runs lint plus hermetic Bats" {
  run uv run --isolated python - "${REPO_ROOT}/.github/workflows/ci.yml" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

expected = {
    "actions/checkout": ("3d3c42e5aac5ba805825da76410c181273ba90b1", "v7.0.1"),
    "actions/setup-go": ("b7ad1dad31e06c5925ef5d2fc7ad053ef454303e", "v7.0.0"),
    "actions/setup-node": ("820762786026740c76f36085b0efc47a31fe5020", "v7.0.0"),
}

# CI has to actually run on changes. This previously asserted the opposite, and
# a dispatch-only workflow is exactly what let failing tests survive on main
# unnoticed; see docs/plans/omarchy-portability-followups.md. The push trigger
# matters alongside pull_request because those tests were failing on main.
assert re.search(
    r"^on:\n"
    r"  workflow_dispatch:\n"
    r"  pull_request:\n"
    r"  push:\n"
    r"    branches:\n"
    r"      - main\n"
    r"\npermissions:\n",
    text,
    re.MULTILINE,
)
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

@test "CI Go version matches the go directive every module declares" {
  # tests/go-tests.bats runs all 17 module suites in CI, so CI's toolchain has
  # to be the one the modules ask for. Deriving the expectation from go.mod
  # rather than restating "1.26" here keeps a Go bump from needing two edits and
  # silently passing with one.
  run uv run --isolated python - "${REPO_ROOT}" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
gomods = subprocess.run(
    ["git", "ls-files", "*go.mod"], cwd=root, capture_output=True, text=True, check=True
).stdout.split()
assert gomods, "no go.mod files tracked"

directives = set()
for rel in gomods:
    for line in (root / rel).read_text(encoding="utf-8").splitlines():
        m = re.fullmatch(r"go\s+(\d+\.\d+(?:\.\d+)?)", line.strip())
        if m:
            directives.add(m.group(1))

assert len(directives) == 1, f"modules disagree on the go directive: {sorted(directives)}"
declared = directives.pop()

ci = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
m = re.search(r"uses:\s*actions/setup-go@[0-9a-f]{40}[^\n]*\n\s*with:\s*\n\s*go-version:\s*\"?([0-9.]+)\"?", ci)
assert m, "ci.yml does not pin a go-version for actions/setup-go"
assert m.group(1) == declared, (m.group(1), declared)
PY

  [ "${status}" -eq 0 ]
}

@test "CI pins every lint tool, including shellcheck" {
  # shellcheck was the one lint tool with no pinned version anywhere: brew on
  # macOS, apt in the devcontainer, and whatever ubuntu-latest shipped in CI.
  # PR #201 passed locally on 0.11.0 and failed CI on 0.9.0 with 449 SC2317
  # findings -- a check 0.9.0 emits and later versions do not. No local run could
  # have reproduced it, because "clean" silently meant "clean on this version".
  run grep -c 'SHELLCHECK_VERSION' "${REPO_ROOT}/.devcontainer/toolchain-versions.sh"

  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]

  # Installed from the pin, not inherited from the runner image.
  run grep -cE 'shellcheck-\$\{SHELLCHECK_VERSION\}\.linux' "${REPO_ROOT}/.github/workflows/ci.yml"

  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

@test "no lint tool is installed in CI without a version" {
  # Generalises the above. Every tool the lint job installs is pinned by an
  # explicit version, a *_VERSION variable, or an @/== specifier. A bare
  # `apt-get install <tool>` or a reliance on the image is what this catches.
  run bash -lc "
    grep -nE '^\s+(uv tool install|npm install --global) ' '${REPO_ROOT}/.github/workflows/ci.yml' |
      grep -vE '(==|@)[0-9]' || true
  "

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "CI Go setup points the cache at the nested go.mod files" {
  # Every go.mod lives under apps/ or tools/; setup-go looks in the workspace
  # root and, finding none, logs "Dependencies file is not found" and disables
  # the module and build caches entirely. The symptom is silent -- a warning,
  # not a failure -- so this asserts the fix rather than the absence of a log.
  run grep -cE '^\s+cache-dependency-path: "\*\*/go\.mod"' "${REPO_ROOT}/.github/workflows/ci.yml"

  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]

  # The setting is worthless if a go.mod ever lands in the root, because
  # setup-go would find that one and cache only it.
  run bash -lc "cd '${REPO_ROOT}' && git ls-files 'go.mod'"

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "CI installs base tools only when the runner image lacks them" {
  # `apt-get update` has taken over six minutes on this job when the Azure
  # mirror Ign:s and the run falls back to archive.ubuntu.com. ubuntu-latest
  # ships all of these already, so the update must be conditional.
  run bash -lc "
    awk '/^          declare -A base_tools=\(/,/^          fi\$/' '${REPO_ROOT}/.github/workflows/ci.yml' |
      grep -c 'apt-get update'
  "

  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  # An unconditional `apt-get update` outside that guard is the regression.
  run bash -lc "
    grep -nE '^          (sudo )?apt-get update' '${REPO_ROOT}/.github/workflows/ci.yml' || true
  "

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
