# Open Items, 2026-08-16

Working tracker for what sections 19 and 20 of
[omarchy-portability-followups.md](omarchy-portability-followups.md) left open.
Each item is closed here only when it is measured, not when it is understood.

Branch: `fix/20260815-macos-portability`. Commits so far: `dab204a1`, `5ed4cf44`.

## 1. Triage the 47 untriaged `kubernetes/*/tests/*.bats`

Section 20.2 made the gap visible and non-growable, then explicitly declined to
claim a triage that had not happened. This is that triage.

Method, following #199: run each safe file in isolation, record fail/total, add
the green ones to `CI_BATS_TESTS`, leave the red ones backlogged with their
measured counts so the remaining job is known rather than guessed. Files that
invoke `docker build/run/compose` are not run unsupervised.

- [x] Classify all 47 as safe-to-run or docker-touching -- 44 safe, 3 docker
- [x] Run the safe set in isolation, record fail/total per file -- 40 green, 4 red
- [x] Fix the 4 reds. **Every one was a stale assertion, not a product bug**
- [x] Add all 44 to `CI_BATS_TESTS`
- [x] Rewrite the backlog comment with measured counts -- 11 entries remain

**Closed.** `make test-ci` 1082/1082, up from 628. The four reds, all invisible
because their files sat outside the gate:

| File | Stale because |
| --- | --- |
| `lima/manage-kubeconfig` | asserted context `lima-k3s`; renamed `limavm-k3s`, and every other test in the file was updated |
| `kind/gitops-refresh` | asserted literal `SECONDS + 300` after the wait moved behind `local.platform_wait_seconds` for `PLATFORM_TIMEOUT_SCALE` |
| `kind/hubble-observe` | asserted `observing namespace <ns>` after the emitter was reworded to `<ns>: capture iteration i/n` (two tests) |
| `kind/check-version` | called coreutils `timeout`, absent on macOS, so it failed on `env: timeout: not found` rather than its subject; two sibling tests already carried that skip guard |

Each fix asserts intent rather than re-pinning a literal, so the next rewording
does not silently re-break them.

## 2. shellcheck: 18 failures, and `make lint` cannot see them

`lint-shell` runs `scripts/audit-shell-scripts.sh`, a *conventions* auditor that
never invokes shellcheck. shellcheck runs only in the lefthook pre-commit hook,
over staged files, so a script is checked once when first committed and never
again.

- [x] Fix the 18 files that fail `shellcheck -x` -- **0 of 207 now fail**
- [x] Add a real shellcheck target and wire it into `make lint`
- [x] Guard: assert `make lint` actually invokes shellcheck, and that the tree stays clean

**Closed.** `make lint` 0, `make test-ci` 1084/1084.

Fixed rather than suppressed wherever the finding was real:

| Fix | Sites |
| --- | --- |
| Quote the pattern in `${x#${y}/}` so a glob char cannot silently skip the strip | 3 |
| Split `export X="$(cmd)"` so the command's exit status is not masked | 2 |
| Delete a genuinely dead assignment (`NAMESPACE_DIR`, written, never read) | 1 |
| Hoist a prefix assignment whose `${STACK_DIR}` read the outer variable, not the prefix | 1 |

The remainder are scoped disables that each state *why* -- functions invoked by
name through the `shell_cli_*` helpers, variables produced by an `eval`'d
`printf 'NAME=%q'` block, positional `read` columns, and values exported for a
subprocess. Two directives had to move above their `case` rather than sit on a
branch, which shellcheck rejects outright.

`scripts/lint-shellcheck.sh` uses `-x` so it and the pre-commit hook cannot
disagree about whether the tree is clean.

## 3. apim-simulator

Separate repo, currently on `main` with a clean tree. Findings from section 20.4's
class, with a worse consequence than either platform instance.

- [x] Escape the backticks in `scripts/generate_walkthroughs.sh:339`
- [x] Repair the spliced build-log lines -- **128 lines per doc, not 62 total**
- [x] Pin `SHELL := /bin/bash` in the Makefile (latent #197 exposure)
- [x] Port the backtick guard, plus a second guard on the symptom
- [ ] The 9/35 shellcheck failures there -- left for its own pass

**Closed** as commit `1cf8f26` on `fix/20260816-executing-docs`. The damage was
larger than first measured: the whole `make up-otel` build log was substituted,
128 lines in `walkthrough-core-stacks.md` and the same again in the doc split
from it. Repaired by hand rather than regenerated -- the note is a fixed
sentence, so the correct content is knowable without a docker run, and it was
checked against the undamaged sibling section's structure.

## 4. Push

Nothing is pushed. Section 19.10 carries the Arch fold-back notes for whoever
picks this up on the Omarchy box.

- [x] Pushed; PR #201 opened

**Note:** the first push failed, and not for a network reason. git opens the SSH
connection *before* running `pre-push`, so a ~12 minute gate outlives it:

```text
🥊 lefthook  v2.1.10   hook: pre-push
Connection to github.com closed by remote host.
```

The hook passed and the push still failed. Pushed with `--no-verify` on the
strength of a `make lint` + `make test-ci` run against that tree, and fixed the
hook in item 5.

## 5. The gate could not finish (follow-up from #201)

- [x] Measure it: 715s serial, 1084 tests, docker down
- [x] Confirm `test-ci` does not need Docker -- **no test in the gate references it**
- [x] Add GNU parallel to the install hints (brew, pacman, apt; **not mise** -- see below)

**Why not mise.** Asked directly, and probed rather than assumed. GNU parallel is
not installable through mise by any route:

| Probe | Result |
| --- | --- |
| `mise registry \| grep parallel` | no entry |
| `mise plugins ls-remote \| grep -ix parallel` | no asdf plugin |
| `mise ls-remote aqua:GNU/parallel` | no aqua-registry package |
| `mise ls-remote github:gnu/parallel` | 404 -- GNU hosts releases on savannah, not GitHub |

So brew/pacman/apt is the whole managed surface, which is what the hints now say.
bats does support an alternative implementation via `--parallel-binary-name` /
`BATS_PARALLEL_BINARY_NAME`, and `run-bats-suite.sh` now passes `PARALLEL_BIN`
through to it -- previously that variable gated detection only, so pointing it at
another binary passed the check and then left bats looking for `parallel`. GNU
parallel remains the only implementation verified against this suite.

- [x] Add `scripts/run-bats-suite.sh` with a guard against the zero-tests trap
- [x] Cut `pre-push` to lint + host-portable subset: **~77s**
- [x] Triage the last three docker-touching tests -- **all three now in the gate**
- [x] Fix the load-sensitive test files (three distinct defects, not six)
- [ ] Diagnose the residual `apps-makefile` flake, then flip `BATS_JOBS` to `auto`

**Three defects, fixed:**

| Test | Defect |
| --- | --- |
| `check-provider-version` | asserted a wall-clock band (>=4s, <6s) *and* wrote to a fixed `/tmp` path, so concurrent runs clobbered each other. Rewritten to measure concurrency directly -- the fake `curl` registers a marker for its lifetime and logs how many exist; asserts peak > 1 and <= 2. Verified it fails at `PLATFORM_PARALLEL_JOBS=1` and at `9`. |
| `check-docker-registry-auth` | 1s timeout against a 2s sleep, about a second of margin. Now 3s against 30s. Scoped to the retry test; its sibling always times out and was never load-sensitive. |
| `makefile.bats` | ours: asserts `CI_BATS_TESTS` is passed sorted, but the parallel/serial split emits two separately-sorted batches. Now checked per invocation, ignoring `--jobs` tokens. Verified it still catches an out-of-order entry. |

**Still `off`, and this is the honest reason.** That took it from "six failures,
never the same six" to **5 clean full runs out of 6**. The sixth failed two tests
in `tests/apps-makefile.bats` -- already in the serial phase, passes alone, and
does not fail beside either its serial neighbours or the three files added just
before it. The residual is load-related and not yet understood. One flake in six
is not a default; the argument for the serial phase was that a gate reporting
different failures each run is worth less than a slow one that does not, and
defaulting to `auto` on 5/6 would contradict it.

**The docker three were never destructive.** They were held back as
"docker build/run/compose", but that came from grepping for the word rather than
reading them: `docker-safe-clean` and `docker-prune-estimate` write a `docker`
stub into `${BATS_TEST_TMPDIR}/bin` and prepend it to `PATH`, so the real binary
is never reached -- they assert on the commands they *would* print. The scripts
under test would indeed destroy a cluster; the tests never call them for real.
`aks-ai-foundry-experiment` gates its two live tests behind
`KIND_AKS_AI_FOUNDRY_LIVE=1` and skips by default. All three run in ~1s. The
`kubernetes/*/tests` backlog is now empty.

**Parallelism is built but deliberately NOT the default.** `BATS_JOBS=auto` takes
the suite from 715s to ~170s, a 4.2x win — and makes the gate flaky. Six files
fail under `--jobs` that pass serially, and *not the same six each run*:

| File | Why |
| --- | --- |
| `platform-workflow` | writes a Terraform lock into `terraform/.run/` in the real repo |
| `release-workflow` | creates a real annotated git tag in the real repo |
| `app-layout-consistency`, `make-target-surfaces`, `apps-makefile` | run `make` against the real tree |
| `check-provider-version`, `dhi-creds-offline` | timing assertions that only fail under load |

The first five are contained by a serial list in `run-bats-suite.sh`. The timing
ones are the reason the default stayed `off`: a 4x faster gate that reports
different failures each run is worth less than a slow one that does not. Opt in
with `make test-ci BATS_JOBS=auto`.

Docker turned out to be a red herring — `make lint` (76s) and `make test-ci`
(1084/1084) both pass with the daemon down, so a preflight would have guarded
nothing. `hubble-observe-cilium-policies.bats` is 141s because of `sleep 1` in
its own stubs, not Docker.

## Log

- 2026-08-16: tracker created.
- 2026-08-16: items 1, 2 and 3 closed. Only item 4 (push) remains, and it needs
  an operator decision rather than a change.
