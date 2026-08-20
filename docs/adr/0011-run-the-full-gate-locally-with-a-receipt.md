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

### Environments

A macOS host gate cannot see Linux-only breakage — Bash 3.2 vs 5, BSD vs GNU
`sed`/`awk`/`grep`, case-insensitive filesystems — and with CI off pull requests
nothing else looks before merge. So a receipt records *which environments*
passed for that tree, not merely that something did.

`make test-ci` records `host`. `make test-ci-linux` re-runs the same suite
inside the devcontainer and records `linux`. Stamping merges into an existing
receipt when the fingerprint matches, and starts over when it does not: a Linux
pass for yesterday's tree proves nothing about today's.

`PLATFORM_GATE_ENVIRONMENTS` (default `host`) is what pre-push insists on.
`host,linux` makes every push carry both, at roughly double the gate time; the
default keeps the fast path and leaves the Linux run for changes that touch
shell or platform behaviour.

The devcontainer run deliberately does **not** write the shared receipt. It
stamps a throwaway one inside `/tmp`, and the host stamps `linux` only after the
container run passes — otherwise a host/container fingerprint disagreement over
bind-mount file modes or ownership would reset the receipt and silently discard
the host result.

### The devcontainer is not a clean room, and the gate has to say so

Its `containerEnv` rewires `KUBECONFIG_PATH` and the registry host alias so the
container can drive the *host's* kind cluster and registry. Run as-is, the gate
measures that wiring rather than Linux: kind reports
`push_host=host.docker.internal`, and lima reports the **kind** kubeconfig,
because `KUBECONFIG_PATH` is set globally to a kind-specific value. So
`run-ci-linux.sh` unsets that wiring, in a plain shell — `bash -lc` re-sources
the profile and puts it straight back.

That global `KUBECONFIG_PATH` is worth fixing in `devcontainer.json` on its own
merits: `KIND_KUBECONFIG_PATH` already exists for the kind-specific value, and
setting the generic one makes every other variant misreport inside the
devcontainer.

### Known residue

Fixing the container toolchain took the devcontainer run from 25 failures to 5.
`make test-ci-linux` therefore does **not** pass yet, and
`PLATFORM_GATE_ENVIRONMENTS` stays `host` by default until it does. What remains
is environment difference, not Linux-only defects:

| test | why |
| --- | --- |
| `configure-k3s-apiserver-oidc` mkcert skip | asserts mkcert is *absent*; the devcontainer installs it |
| `kubernetes-sso-runner` Playwright wiring | pins the Docker bridge IP `172.17.0.1`, which differs under docker-outside-of-docker |
| `makefile` root lint delegation | `make lint` needs markdownlint-cli2, biome and deno, which CI installs and the devcontainer does not |
| `opentofu-tier` fast tier | provider plugin init inside the container |
| `variant-contracts` Makefile defaults | kind's `push_host` is legitimately the host alias in a container |

Each wants either a container-aware assertion or the missing tool installed, and
each is separable.

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
