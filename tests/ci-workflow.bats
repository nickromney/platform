#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "local Lefthook gate owns all verification and GitHub retains only release publishing" {
  run uv run --locked --project "${REPO_ROOT}" python - "${REPO_ROOT}" <<'PYTEST'
from pathlib import Path
import sys
import yaml
root = Path(sys.argv[1])
workflows = sorted(path.name for path in (root / ".github/workflows").glob("*.y*ml"))
assert workflows == ["release.yml"], workflows
hook = yaml.safe_load((root / "lefthook.yml").read_text())
assert hook["pre-push"]["commands"]["local-ci"]["run"] == "uv run --locked scripts/hooks/run-local-ci.sh --execute"
runner = (root / "scripts/hooks/run-local-ci.sh").read_text()
assert 'uv run --locked --project "${HOOKS_REPO_ROOT}" make lint' in runner
assert 'uv run --locked --project "${HOOKS_REPO_ROOT}" make test-ci' in runner
assert '--action verify' in runner
assert 'PLATFORM_LOCAL_CI_FULL' in runner
PYTEST
  [ "${status}" -eq 0 ]
}

@test "local Go toolchain pin matches every nested module directive" {
  run uv run --locked --project "${REPO_ROOT}" python - "${REPO_ROOT}" <<'PYTEST'
from pathlib import Path
import re
import subprocess
import sys
root=Path(sys.argv[1])
modules=subprocess.check_output(["git","ls-files","*go.mod"],cwd=root,text=True).split()
assert modules
versions={re.search(r"^go\s+(\d+\.\d+)(?:\.\d+)?",(root/path).read_text(),re.M).group(1) for path in modules}
assert len(versions)==1,versions
pins=(root/".devcontainer/toolchain-versions.sh").read_text()
version=versions.pop()
assert re.search(r'GO_VERSION="\$\{GO_VERSION:-'+re.escape(version)+r'(?:\.\d+)?\}"',pins),version
PYTEST
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

  # Installed from the pin, not inherited from the runner image. The archive
  # name is parameterized by OS so the same installer can grow a macOS job
  # later; CI today only runs this on Linux.
  run grep -cE 'shellcheck-\$\{SHELLCHECK_VERSION\}\.\$\{os_name\}' "${REPO_ROOT}/scripts/ci/install-ci-toolchain.sh"

  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

@test "no lint tool is installed in CI without a version" {
  # Generalises the above. Every tool the lint job installs is pinned by an
  # explicit version, a *_VERSION variable, or an @/== specifier. A bare
  # `apt-get install <tool>` or a reliance on the image is what this catches.
  installer="${REPO_ROOT}/scripts/ci/install-ci-toolchain.sh"

  run grep -nE '^(uv tool install|npm install --global) ' "${installer}"

  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  # Pin forms, not a regex: `bash -lc "... \$\{ ..."` eats the braces, and BSD
  # grep treats `\{` as a bound. `==${PIN}` / `@${PIN}` / `==1.2.3` / `@1.2.3`.
  unpinned="$(
    grep -nE '^(uv tool install|npm install --global) ' "${installer}" |
      grep -vF '==${' |
      grep -vF '@${' |
      grep -vE '(==|@)[0-9]' || true
  )"

  [ -z "${unpinned}" ]
}

@test "CI toolchain installer defaults to dry-run and reads the pin source" {
  # The workflow only calls this with --execute. Without that flag it must not
  # curl anything: a missing --execute in YAML would otherwise look like a
  # successful step that installed nothing.
  installer="${REPO_ROOT}/scripts/ci/install-ci-toolchain.sh"

  run "${installer}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage:"* ]]
  [[ "${output}" == *"INFO dry-run: would install the pinned CI toolchain into /usr/local/bin"* ]]

  grep -Fq 'source .devcontainer/toolchain-versions.sh' "${installer}"
  grep -Fq 'yamllint==${YAMLLINT_VERSION}' "${installer}"
  grep -Fq 'ruff==${RUFF_VERSION}' "${installer}"
  grep -Fq 'markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}' "${installer}"
  grep -Fq '@biomejs/biome@${BIOME_VERSION}' "${installer}"
  grep -Fq 'deno_version="${DENO_VERSION#v}"' "${installer}"
  grep -Eq '^bats_version="[0-9]+\.[0-9]+\.[0-9]+"' "${installer}"
  grep -Fq 'could not parse uv version from .devcontainer/Dockerfile' "${installer}"
}

@test "local Go gate discovers every nested module instead of depending on a root module" {
  [ ! -f "${REPO_ROOT}/go.mod" ]
  grep -Fq "go.mod" "${REPO_ROOT}/tests/go-tests.bats"
  grep -Fq "go test" "${REPO_ROOT}/tests/go-tests.bats"
}

@test "CI installs base tools only when the runner image lacks them" {
  # `apt-get update` has taken over six minutes on this job when the Azure
  # mirror Ign:s and the run falls back to archive.ubuntu.com. ubuntu-latest
  # ships every package named here, and ripgrep -- the one thing it does not
  # ship that the gate needs -- comes from its pinned release instead, so the
  # apt path should not run at all. It stays as a fallback for a changed image.
  installer="${REPO_ROOT}/scripts/ci/install-ci-toolchain.sh"

  # Count the command, not the comments that name it. `grep -cF 'apt-get update'`
  # was 3: two prose mentions plus the one sudo call this is pinning.
  run grep -cE '^[[:space:]]*sudo apt-get update$' "${installer}"

  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -cF 'installing missing base tools' "${installer}"

  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  # The workflow must not grow its own apt path now the installer owns it.
  run bash -lc "grep -nF 'apt-get' '${REPO_ROOT}/scripts/hooks/run-local-ci.sh' || true"

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

@test "local verification does not modify the developer Homebrew taps" {
  run grep -En 'brew untap|HOMEBREW_NO_REQUIRE_TAP_TRUST[[:space:]]*[:=]' "${REPO_ROOT}/scripts/hooks/run-local-ci.sh"
  [ "${status}" -eq 1 ]
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
  run grep -Fn 'https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/${ripgrep_dir}.tar.gz' "${REPO_ROOT}/scripts/ci/install-ci-toolchain.sh"

  [ "${status}" -eq 0 ]

  # And never from apt, which is the regression this replaced.
  run bash -lc "
    awk '/missing_packages=\(\)/,/skipping apt/' '${REPO_ROOT}/scripts/ci/install-ci-toolchain.sh' |
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
