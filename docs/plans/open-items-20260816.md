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

- [ ] Fix the 18 files that fail `shellcheck -x`
- [ ] Add a real shellcheck target and wire it into `make lint`
- [ ] Guard: assert `make lint` actually invokes shellcheck

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

- [ ] Confirm with the operator before pushing (outward-facing, needs a decision)

## Log

- 2026-08-16: tracker created.
