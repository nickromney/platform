# ADR 0011: Run the full gate locally, verified by a receipt, and take CI off pull requests

- Status: Accepted
- Recorded: 2026-08-19

## Context

The full gate is `make lint && make test-ci`: about 90 seconds of lint plus
~12 minutes of 156 Bats files. Where it runs has been decided twice before, and
both decisions were right for their moment and wrong later.

**It cannot live in `pre-push`.** git opens the SSH connection to the remote
*before* running the hook, so a twelve-minute hook outlives it: the gate passes
and the push then dies with "Connection to github.com closed by remote host". A
gate that prevents the operation it guards is not a gate. That is why pre-push
ran only `make lint` plus an 8-file host-portable subset.

**"CI will catch it" stopped being an acceptable answer.** With an 8-file local
subset against 156 in CI, a clean push carried almost no evidence. PR #206
pushed green locally and went red on GitHub with four failures — three of them
tests asserting on files a refactor had emptied, exactly the cross-cutting
breakage a subset cannot see.

The obvious response is to lean harder on GitHub. That got worse, not better:
the same job spent over six minutes inside `apt-get update` when the Azure
mirror stalled and the run fell back to `archive.ubuntu.com`, and every push to
an open PR queued another full remote run. The feedback loop had moved somewhere
we do not control and cannot make faster.

There is also a prior lesson not to undo. CI was once `workflow_dispatch`-only,
and failing tests survived on `main` unnoticed
(`docs/plans/omarchy-portability-followups.md`). Whatever changes, `main` must
stay watched.

## Decision

Run the full gate locally, and prove it ran with a receipt.

- `make test-ci`, on success, stamps `.run/ci-receipt.json` with a fingerprint
  of the exact working tree it verified.
- `pre-push` runs `make lint` (~90 seconds, well inside the SSH budget) and then
  *verifies* that receipt against the tree being pushed. Match: passes in
  milliseconds. Stale or missing: refuses, and names the command to run.
- `PLATFORM_LOCAL_CI_FULL=1` still runs the whole suite inside the push, for
  anyone who wants it and accepts the timeout risk.

The fingerprint is a **git tree hash of the working tree's content**, built by
staging into a throwaway index (`GIT_INDEX_FILE`) so the real index is untouched.
Two requirements pull against each other and only a content hash satisfies both:

- It must be sensitive to uncommitted and untracked-but-not-ignored edits, or a
  receipt keeps passing while work piles up underneath it — the precise way
  "I ran the tests" becomes untrue.
- It must be **invariant across `git commit`**. The normal sequence is run the
  gate, commit, push. Committing changes `HEAD` and empties `git diff HEAD`
  while changing no file at all, so a fingerprint built from either would
  invalidate itself at the commit and demand a second twelve-minute run for a
  tree the gate had already verified. The first draft of this had that bug.

The receipt file is excluded from its own fingerprint explicitly, so the design
does not silently depend on `.run/` staying in `.gitignore`.

A receipt is valid because the tree still matches, **not** because it is recent.
There is no expiry: an hour-old receipt on an unchanged tree is exactly as good
as a fresh one, and a receipt from thirty seconds ago is worthless if a file
changed after it.

GitHub CI drops its `pull_request` trigger and keeps `push: branches: [main]`
and `workflow_dispatch`. It stops being the feedback loop and becomes the
evidence local runs cannot produce: the protected line, and the macOS job that
covers Bash 3.2 and BSD awk from a Linux host. Run it against a branch on demand
with `gh workflow run ci.yml --ref <branch>`.

## Consequences

- The feedback loop is local and does not queue behind GitHub.
- The full 156 files now gate every push, where 8 did before. Coverage went up,
  not down, even though remote CI runs less.
- **You must run `make test-ci` yourself before pushing.** The hook tells you
  when the receipt is stale rather than silently running twelve minutes.
- A PR carries no automated remote evidence unless someone dispatches the
  workflow. Reviewers must not read "no checks" as "not tested"; the receipt is
  the evidence, and it is local. Dispatch the workflow for anything where remote
  confirmation matters.
- `push: branches: [main]` is load-bearing and must not be removed. Dropping it
  too would reproduce the dispatch-only hole. `tests/ci-workflow.bats` asserts
  the trigger and, separately, that the receipt gate is still wired — so
  removing the local control cannot quietly follow removing the remote one.
- The macOS job only runs on `main` and on demand now, so Bash 3.2 regressions
  surface later than they used to. That is the real cost of this decision.
- Receipts live in `.run/`, which is gitignored, so they are per-checkout and
  never shared. A receipt says nothing about anyone else's tree.

## Evidence

- [scripts/ci-receipt.sh](../../scripts/ci-receipt.sh)
- [scripts/hooks/run-local-ci.sh](../../scripts/hooks/run-local-ci.sh)
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml)
- [tests/ci-workflow.bats](../../tests/ci-workflow.bats)
- [docs/plans/HANDOFF-20260819.md](../plans/HANDOFF-20260819.md)
- Related: [ADR 0010](./0010-share-variant-lifecycle-and-workflow-core.md), whose
  refactor produced the CI failure that motivated this
