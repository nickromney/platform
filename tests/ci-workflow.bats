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

# The push-to-main trigger is the load-bearing one and must not be removed. A
# dispatch-only workflow is what let failing tests survive on main unnoticed;
# see docs/plans/omarchy-portability-followups.md.
#
# pull_request was dropped deliberately (ADR 0011): the full gate now runs
# locally, gated by the make test-ci receipt that pre-push verifies. That is a
# compensating control, not an absence of one -- the companion test below
# asserts the hook still enforces it, so this cannot decay back into
# dispatch-only with nothing watching.
assert re.search(
    r"^on:\n"
    r"  workflow_dispatch:\n"
    r"  push:\n"
    r"    branches:\n"
    r"      - main\n"
    r"\npermissions:\n",
    text,
    re.MULTILINE,
)
assert "pull_request:" not in text, "re-adding pull_request needs a deliberate decision; see ADR 0011"
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
  # ships every package named here, and ripgrep -- the one thing it does not
  # ship that the gate needs -- comes from its pinned release instead, so the
  # apt path should not run at all. It stays as a fallback for a changed image.
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

@test "dropping pull_request leaves the local receipt gate enforcing the full suite" {
  # ci.yml no longer runs on pull_request, so the full suite's only routine
  # enforcement is local. These three facts are what make that safe; if any one
  # of them goes, the gate is gone and nothing else reports it.

  # 1. make test-ci stamps a receipt, and only when the run passed.
  run grep -Fn 'if [ "$$rc" -eq 0 ]; then "$(CI_RECEIPT_SCRIPT)" --execute --action stamp; fi' "${REPO_ROOT}/Makefile"

  [ "${status}" -eq 0 ]

  # 2. The pre-push hook verifies that receipt against the tree being pushed.
  run grep -Fn 'scripts/ci-receipt.sh" --execute --action verify' "${REPO_ROOT}/scripts/hooks/run-local-ci.sh"

  [ "${status}" -eq 0 ]

  # 3. lefthook actually wires that script into pre-push.
  run grep -Fn 'scripts/hooks/run-local-ci.sh --execute' "${REPO_ROOT}/lefthook.yml"

  [ "${status}" -eq 0 ]
}

@test "the gate receipt survives committing but not editing" {
  # Both halves matter and they pull against each other.
  #
  # Sensitive to edits, or a receipt keeps passing while uncommitted work piles
  # up underneath it, which is how "I ran the tests" becomes untrue.
  #
  # Invariant across `git commit`, or the normal sequence -- run the gate,
  # commit, push -- invalidates itself at the commit and demands a second
  # twelve-minute run for a tree already verified. A fingerprint built from HEAD
  # or from `git diff HEAD` fails this half, which is why it hashes content.
  #
  # Exercised against a throwaway repo rather than this one, so the assertions
  # can commit freely.
  script="${REPO_ROOT}/scripts/ci-receipt.sh"
  work="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${work}"

  (
    cd "${work}"
    git init -q
    git config user.email test@example.com
    git config user.name Test
    # The developer's global config may sign commits through an external agent
    # (1Password here), which is not reachable from a Bats sandbox.
    git config commit.gpgsign false
    git config tag.gpgsign false
    printf 'one\n' >tracked.txt
    git add tracked.txt
    git commit -qm initial
  )

  # A gate run against this tree, then real work committed on top of it.
  REPO_ROOT="${work}" run "${script}" --execute --action stamp
  [ "${status}" -eq 0 ]

  printf 'two\n' >"${work}/tracked.txt"
  printf 'new\n' >"${work}/untracked.txt"

  # Edits are not yet covered by the receipt.
  REPO_ROOT="${work}" run "${script}" --execute --action verify
  [ "${status}" -ne 0 ]

  # Re-run the gate, then commit exactly what it verified.
  REPO_ROOT="${work}" run "${script}" --execute --action stamp
  [ "${status}" -eq 0 ]

  (
    cd "${work}"
    git add -A
    git commit -qm "work"
  )

  # The commit changed HEAD but no file content, so the receipt still holds.
  REPO_ROOT="${work}" run "${script}" --execute --action verify
  [ "${status}" -eq 0 ]

  # A post-commit edit invalidates it again.
  printf 'three\n' >"${work}/tracked.txt"
  REPO_ROOT="${work}" run "${script}" --execute --action verify
  [ "${status}" -ne 0 ]
}

@test "the gate receipt leaves the real index alone" {
  # The fingerprint stages the working tree to hash it. Doing that in the real
  # index would silently rewrite what the user had staged.
  before="$(git -C "${REPO_ROOT}" status --porcelain -unormal)"

  run bash -lc "cd '${REPO_ROOT}' && ./scripts/ci-receipt.sh --execute --action fingerprint"

  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9a-f]{40}$ ]]

  grep -Fq 'GIT_INDEX_FILE' "${REPO_ROOT}/scripts/ci-receipt.sh"

  [ "$(git -C "${REPO_ROOT}" status --porcelain -unormal)" = "${before}" ]
}

@test "the macOS job does not fight the runner's Homebrew taps" {
  # The runner image ships untrusted third-party taps and Homebrew prints a
  # trust notice for each one. It is cosmetic -- bats-core, jq and yq are all
  # homebrew/core.
  #
  # Untapping them was tried and reverted: Homebrew refuses to untap a tap
  # holding installed formulae (bicep, packer) and writes that refusal to
  # stderr, which Actions renders as a red ##[error] on an otherwise passing
  # job. This pins the revert so the notice does not invite the same fix twice.
  run grep -Fn 'brew untap' "${REPO_ROOT}/.github/workflows/ci.yml"

  [ "${status}" -ne 0 ]

  # Nor silenced with the variable Homebrew documents as deprecated. Matches it
  # being set, not the comment naming it.
  run grep -nE 'HOMEBREW_NO_REQUIRE_TAP_TRUST[[:space:]]*[:=]' "${REPO_ROOT}/.github/workflows/ci.yml"

  [ "${status}" -ne 0 ]
}

@test "ripgrep is pinned and installed from its release, not from apt" {
  # Ten gated Bats files call `rg`, and ubuntu-latest does not ship it. Getting
  # it from apt made every run pay for apt-get update, which is where the
  # six-minute Azure-mirror stalls happened. Pinned like shellcheck and kyverno,
  # and cooldown-governed through the same machinery as every other pin.
  run grep -cE '^RIPGREP_VERSION="\$\{RIPGREP_VERSION:-[0-9]' "${REPO_ROOT}/.devcontainer/toolchain-versions.sh"

  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  # Registered for the version audit, or the pin silently stops being tracked.
  # BSD grep has no -P, so the tabs are literal rather than escapes.
  run grep -cxF "ripgrep	github:BurntSushi/ripgrep	RIPGREP_VERSION" "${REPO_ROOT}/.devcontainer/toolchain-sources.tsv"

  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  # Fetched from the pin in CI.
  run grep -Fn 'https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/${ripgrep_dir}.tar.gz' "${REPO_ROOT}/.github/workflows/ci.yml"

  [ "${status}" -eq 0 ]

  # And never from apt, which is the regression this replaced.
  run bash -lc "
    awk '/^          declare -A base_tools=\(/,/^          fi\$/' '${REPO_ROOT}/.github/workflows/ci.yml' |
      grep -c 'ripgrep' || true
  "

  [ "${status}" -eq 0 ]
  [ "${output}" -eq 0 ]
}

@test "the receipt accumulates environments for one tree and resets for another" {
  # The host gate cannot see Linux-only breakage, so make test-ci-linux re-runs
  # the suite in the devcontainer and records itself on the same receipt. Two
  # properties matter and pull against each other: the two runs happen minutes
  # apart and must merge, but a linux pass must not survive an edit -- a green
  # Linux result for yesterday's code proves nothing about today's.
  receipt="${BATS_TEST_TMPDIR}/receipt.json"
  work="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${work}"

  (
    cd "${work}"
    git init -q
    git config user.email test@example.com
    git config user.name Test
    git config commit.gpgsign false
    printf 'one\n' >tracked.txt
    git add tracked.txt
    git commit -qm initial
  )

  run env REPO_ROOT="${work}" CI_RECEIPT_FILE="${receipt}" \
    "${REPO_ROOT}/scripts/ci-receipt.sh" --execute --action stamp
  [ "${status}" -eq 0 ]

  # host alone does not satisfy a host+linux requirement.
  run env REPO_ROOT="${work}" CI_RECEIPT_FILE="${receipt}" PLATFORM_GATE_ENVIRONMENTS=host,linux \
    "${REPO_ROOT}/scripts/ci-receipt.sh" --execute --action verify
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"does not cover: linux"* ]]
  [[ "${output}" == *"make test-ci-linux"* ]]

  # The devcontainer run merges rather than replacing.
  run env REPO_ROOT="${work}" CI_RECEIPT_FILE="${receipt}" \
    "${REPO_ROOT}/scripts/ci-receipt.sh" --execute --action stamp --environment linux
  [ "${status}" -eq 0 ]

  run env REPO_ROOT="${work}" CI_RECEIPT_FILE="${receipt}" PLATFORM_GATE_ENVIRONMENTS=host,linux \
    "${REPO_ROOT}/scripts/ci-receipt.sh" --execute --action verify
  [ "${status}" -eq 0 ]

  # An edit invalidates both, and a fresh host stamp must not resurrect linux.
  printf 'two\n' >"${work}/tracked.txt"
  run env REPO_ROOT="${work}" CI_RECEIPT_FILE="${receipt}" \
    "${REPO_ROOT}/scripts/ci-receipt.sh" --execute --action stamp
  [ "${status}" -eq 0 ]

  run env REPO_ROOT="${work}" CI_RECEIPT_FILE="${receipt}" PLATFORM_GATE_ENVIRONMENTS=host,linux \
    "${REPO_ROOT}/scripts/ci-receipt.sh" --execute --action verify
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"does not cover: linux"* ]]
}

@test "the devcontainer gate does not write the shared receipt itself" {
  # If the container stamped directly, a host/container fingerprint disagreement
  # -- bind-mount file modes, ownership -- would reset the receipt and silently
  # discard the host result. The container writes a throwaway receipt; the host
  # stamps linux only after the container run passes.
  script="${REPO_ROOT}/scripts/run-ci-linux.sh"

  # Asserts the intent, not the exact line: the container run must send its
  # receipt somewhere disposable, and the shared stamp must happen on the host
  # afterwards. An earlier version pinned the literal command and broke the
  # moment the script gained `env -u ...` -- the same shape as the grep
  # contracts this branch already had to repoint.
  grep -Fq 'CI_RECEIPT_FILE=/tmp/platform-linux-receipt.json' "${script}"
  grep -Eq '(^|[^-])make test-ci' "${script}"
  grep -Fq -- '--action stamp --environment linux' "${script}"

  # The stamp must come after the container run, or a failing suite still counts.
  run bash -lc "
    container_line=\$(grep -n 'CI_RECEIPT_FILE=/tmp/platform-linux-receipt.json' '${script}' | cut -d: -f1)
    stamp_line=\$(grep -n -- '--action stamp --environment linux' '${script}' | cut -d: -f1)
    [ \"\${container_line}\" -lt \"\${stamp_line}\" ]
  "

  [ "${status}" -eq 0 ]

  grep -Fq 'test-ci-linux:' "${REPO_ROOT}/Makefile"
}
