# Omarchy Portability Follow-Ups

Findings from moving the primary workstation from macOS to Omarchy (Arch Linux)
on 2026-08-12. The portability work itself landed in PR #195; this records what
that pass uncovered but did not fix.

Stage 900 does come up on Arch: 89 pods Running, zero unhealthy.

## The Shape Of The Problem

Very little of the macOS coupling was `brew` or `uname -s` branching. Almost all
of it was **Docker Desktop quietly papering over a difference**, so a Desktop
behaviour had been encoded as a platform assumption:

| Assumption | Reality on Docker Engine |
| --- | --- |
| `host.docker.internal` resolves | Does not exist; Desktop injects it |
| `docker push` of a multi-arch tag works | containerd image store keeps an index; push fails |
| An empty Docker config still pulls | Every pull becomes anonymous; `dhi.io` 401s |
| Docker runs a fixed-size VM | Engine shares host RAM; no memory slider exists |

Worth applying that lens to anything else Desktop provides for free.

A second axis showed up alongside it: **machine speed**. Several failures were
not logic errors but hardcoded timeouts on slower hardware.

## 1. The Safety Net Is Not Catching Regressions

Highest value item here.

The release-age cooldown gate had **never once passed** for a tool bump, because
`epoch_from_iso` appended a second `Z` to GitHub timestamps. Three tests in
`tests/update-versions.bats` were already failing on `main` as a result,
verified against a pristine `HEAD` worktree.

Three more fail in `kubernetes/kind/tests/makefile.bats`:

- `kind help documents the 920 stage ladder` asserts the output contains no
  `$HOME`, but invokes `make -C`, which prints `Entering directory '<abspath>'`.
  **This fails for any user whose repo lives under their home directory.** Fix
  with `--no-print-directory` or by filtering the line in the test.
- `kind conflict preflight allows running Lima VMs with no host bindings`
- `kind check-version can emit a combined machine-readable JSON report`

CI runs bats on `ubuntu-latest`, and lefthook's `pre-push` runs `local-ci`. Both
should have caught this. **A broken supply-chain gate surviving this long is
more concerning than the bug itself.**

Resolved on 2026-08-13, and the answer is worse than "green for an
environmental reason" — neither mechanism runs at all:

- `.github/workflows/ci.yml` is `on: workflow_dispatch:` only. No `push`, no
  `pull_request`. The `lint-and-hermetic-bats` job has never executed against a
  PR. `gh run list --branch <any-feature-branch>` returns nothing.
- `version-audit.yml` does fire weekly on `cron: '0 9 * * 1'`, and has failed
  every run for at least a month (27 Jul, 3 Aug, 10 Aug), each in 8-17s:

  ```text
  uv not found in PATH
  make: *** [Makefile:283: check-version] Error 1
  ```

  It was dying before reaching the audit, so the schedule proved nothing.

The host half of that is fixed: `uv` is now pinned in the n-dotfiles global mise
config next to `ruff`, so it installs on every machine rather than being a
manual step. `make check-version` passes end to end locally.

Both remaining changes landed on 2026-08-13:

- `ci.yml` now triggers on `pull_request` and on `push` to `main`. The push
  trigger matters as much as the PR one, because the failing tests this section
  describes were failing *on `main`*, which a PR-only trigger would not catch.
- `version-audit.yml` now installs `uv` through `astral-sh/setup-uv` and pins
  `helm` from `toolchain-versions.sh`. `uv` alone was not enough: the component
  guard calls `require helm` unconditionally in `main()`, so the workflow would
  have moved its failure one step later rather than passing.

Both tool versions are read from the files that already own them
(`.devcontainer/Dockerfile` for `uv`, `toolchain-versions.sh` for `helm`) rather
than restated in the workflow, so this cannot become another drift source.

The four failing tests are also fixed. Three of the four shared a single cause:
`make -C` prints `Entering directory '<abspath>'`, which broke a `$HOME`
assertion, an empty-output assertion, and a `jq` parse of a JSON report.
`--no-print-directory` on those three invocations resolves all of them. The
fourth was environmental in the same family as the rest of this document: `perl`
warns when the host locale is not installed, and those warnings landed in the
middle of the report. The rewrites are byte-level pin substitutions, so they now
run under `LC_ALL=C`.

`perl` was also an undeclared dependency of `update-versions.sh`, which guarded
`curl`, `jq` and `awk` but not `perl`. Since the pin rewrites are in place edits
applied one pin at a time, a missing `perl` would have left the toolchain file
partially rewritten, so both apply paths now check for it up front.

Enabling the triggers immediately surfaced five more failing tests on `main`,
none of them caused by this change and all verified against a pristine `HEAD`.
That is the strongest evidence for this section's claim: `make test-ci` had not
been running anywhere that anyone was looking.

Two were the *same* two root causes as the original four:

- `tests/makefile.bats` asserts an exact JSON match on `make -C ... status`, so
  the `Entering directory` line broke it. Fourth instance of that one bug.
- `sync-gitea-policies.sh` also rewrites with `perl`, and the locale warnings
  landed inside two rendered golden outputs. The `LC_ALL=C` fix now covers every
  `perl -0pi` call in that script too, not just `update-versions.sh`.

The other three were host-dependence of a different shape, where the test result
depends on what the machine happens to have installed:

- `tests/trivy-runner.bats` has two cases asserting the "trivy is missing"
  behaviour, but the suite prepends its sandbox to the real `PATH`. A host with
  trivy from mise fails both, while CI passed them for the wrong reason:
  `ubuntu-latest` simply has no trivy. They now scrub trivy from `PATH`.
- `tests/platform-status.bats` stubs `limactl` but not `k3sup`. The lima NOTE
  column shows only the first blocker, so with no `k3sup` on the host the
  "bootstrap client not found" blocker displaces the shared-host-ports one the
  test asserts on. This passed only inside the devcontainer, where arkade
  installs `k3sup`, and would have failed on the CI runner. It now stubs
  `k3sup` alongside `limactl`.

The pattern worth carrying forward: a test in the "hermetic" subset that reads
host state is not hermetic, and it fails in exactly one direction depending on
which machine runs it.

### Correction 2026-08-14: the locale sweep looked for the wrong word

The `LC_ALL=C` fix above was applied to every `perl` invocation, and that was
the wrong search. Running `make -C kubernetes/kind 900 apply` on this host
printed **831 lines** of Perl locale warnings before reaching any real work.

The offender is `shasum`, which is itself a Perl script. Nothing at the call
site says `perl`, so grepping for `perl` could never have found it:

```bash
find "$@" -type f -print |
  LC_ALL=C sort |                 # author knew about locale here
  while IFS= read -r source_file; do
    shasum -a 256 "${source_file}"  # ... but not here
  done
```

`source_fingerprint_tag` in `kubernetes/workflow/image-catalog-lib.sh` calls it
once per source file, so a single invocation produced roughly sixty 14-line
warnings. The whole subshell now runs under `LC_ALL=C`, which is correct beyond
the warnings: every step is byte-level and must not vary by host. The resulting
digest is unchanged, verified against real files, so no image rebuilds are
triggered. The remaining seven `shasum` call sites across four scripts were
swept too.

`make -C kubernetes/kind 900 plan` under the broken locale now emits zero
warnings, down from 831.

**The host is also misconfigured, and that is the real root cause.**
`~/.zshrc:56` exports `LANG="en_GB.UTF-8"`, but `/etc/locale.gen:154` still has
`#en_GB.UTF-8 UTF-8` commented out, so that locale was never generated. Only
`C.utf8` and `en_US.utf8` exist, and `/etc/locale.conf` disagrees with the
shell by naming `en_US.UTF-8`. Every Perl-backed tool on the machine warns,
not just this repo's:

```shell
sudo sed -i 's/^#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
```

The repo fix and the host fix are both worth having: the host fix stops the
warnings everywhere, and the repo fix means the platform does not depend on any
particular host getting its locale right.

Guarded by `tests/locale-independence.bats`, which asserts the behaviour under
a deliberately uninstalled locale rather than the spelling of the command,
plus a static backstop that every tracked `shasum` call site sits in an
`LC_ALL=C` scope. Verified to fire by reverting one call site.

### Fixing the host locale exposed a second, latent bug

Worth stating on its own, because it is the opposite of what a fix usually
does. Once `en_GB.UTF-8` was actually generated, `sort` began using en_GB
collation instead of falling back to `C`, and
`tests/sentiment-go-only.bats` started failing:

```text
LC_ALL=C sort   -> .gitea, MODEL_CARD.md, Makefile, README.md, app, ...
en_GB.UTF-8     -> app, catalog-info.yaml, compose.tls.yml, ...
```

en_GB collation ignores the leading dot and folds case; `C` does not. The test
asserts an exact `ls -A | sort` listing written in `C` order, so it had been
passing only because the host locale was broken. The sort now runs under
`LC_ALL=C`.

The general shape: a broken locale silently pins collation to `C`, so any
comparison that assumed `C` keeps working. Repairing the locale is what makes
those assumptions visible. Anywhere the repo sorts and then compares against a
fixed expectation — golden files, exact-match assertions, hashes over sorted
input — needs `LC_ALL=C` stated explicitly rather than inherited by accident.

`tests/ci-workflow.bats` asserted `pull_request` and `push` were *absent* from
`ci.yml`, with no recorded reason. That assertion encoded the defect this
section describes, so it now requires the triggers instead. While updating it,
`tests/version-audit-workflow.bats` turned out to check only a known list of
actions rather than all of them, so an unpinned action could have been added
without failing anything. It now asserts the set of actions used is exactly the
set pinned, which matters most in the workflow that audits supply-chain versions.

## 2. Timeouts Assume Fast Hardware

On a 16GB laptop with a slower chipset, these timed out while the underlying
work succeeded anyway:

- `hubble-ui` rollout: 300s `local-exec` timeout, deployment completed on its own
- `keycloak`: 14m30s deadline exceeded
- `unset-gitea-must-change-password.sh`: gitea admin CLI readiness
- argocd repo-server: manifest generation deadline

`preload-images.sh` already parameterises its timeouts
(`PRELOAD_DOCKER_PULL_TIMEOUT_SECONDS` and friends). The Terraform `local-exec`
waits are hardcoded. Introduce a `PLATFORM_TIMEOUT_SCALE` (default `1`)
multiplied into those waits, so a slow host sets `2` or `3` rather than editing
`.tf` files.

Done on 2026-08-13. `var.platform_timeout_scale` feeds a
`local.platform_wait_seconds` map in `terraform/kubernetes/locals.tf`, and the
kind Makefile exports `PLATFORM_TIMEOUT_SCALE` as `TF_VAR_platform_timeout_scale`.
Every value equals its previous hardcoded default at scale `1`, so nothing
changes until an operator opts in:

```shell
make -C kubernetes/kind 900 apply PLATFORM_TIMEOUT_SCALE=3
```

Covered: the hubble-ui and cilium rollouts, the argocd repo-server waits, the
gitea rollout and SSH readiness deadlines, the node-Ready wait, the headlamp and
langfuse rollouts, and the two 1800s helm release timeouts.

## 3. Readiness Race In eso-demo

Distinct from the timeouts above, and a real ordering bug.

Argo applied `ExternalSecret` and `SecretStore` while `external-secrets-webhook`
was still refusing connections:

```text
failed calling webhook "validate.externalsecret.external-secrets.io":
dial tcp 10.96.119.89:443: connect: connection refused (retried 5 times)
```

A manual resync once the webhook was Ready fixed it permanently
(`SecretSynced/True`). Proper fix: `argocd.argoproj.io/sync-wave` ordering so
`eso-demo` lands after the webhook is Ready, or a retry policy that tolerates
webhook connection errors.

Resolved on 2026-08-13 with the retry policy, because the wave ordering was
already correct and was not the gap. `external-secrets` is wave 86 and
`eso-demo` is wave 87; the problem is that a wave advances once the Application
reports healthy, which does not mean the webhook Service is accepting
connections. `eso-demo` now carries the same retry profile as
`cert-manager-config`, the other config app that lands behind a webhook
(`limit: 20`, 15s backoff, factor 2, 5m cap).

## 4. gitea Argo Comparison Never Completes

`gitea` sits at `sync=Unknown, health=Healthy`. The workload is fine; only Argo's
comparison fails:

```text
Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = DeadlineExceeded desc = context deadline exceeded
```

Not isolated. Known facts:

- The host reaches `https://dl.gitea.io/charts/index.yaml` in 0.28s
- A busybox pod in the same cluster fetched it successfully over IPv4
- `helm repo add` inside the repo-server pod hangs past 120s
- Pod DNS returns both A and AAAA; A records resolve and egress works

An IPv6 explanation was considered and **disproved**. Remaining candidates: a
Cilium egress policy on the `argocd` namespace, or a helm cache/permissions
problem in the repo-server image. Start by comparing a shell in the repo-server
pod against the same request from a plain pod in the same namespace.

### Resolved 2026-08-14: the Cilium candidate was right

The fix is one line: allowlist the redirect target.

`dl.gitea.io` 301s to `dl.gitea.com`. `argocd-repo-server-helm-egress` (in
`cluster-policies/cilium/shared/argocd-hardened.yaml`) allowlisted only
`dl.gitea.io`, so helm followed the redirect into a destination the policy did
not permit. A `toFQDNs` allowlist applies to the redirect target as well as the
requested name.

Confirmed by drop trace rather than inference. With only `dl.gitea.io` allowed,
`cilium-dbg monitor --type drop --related-to <repo-server-endpoint>` shows:

```text
xx drop (Policy denied) ... identity 4892->world: 10.244.1.142:36662 -> 172.67.75.17:443 tcp SYN
xx drop (Policy denied) ... identity 4892->world: 10.244.1.142:45904 -> 104.26.2.246:443 tcp SYN
```

Both destinations are `dl.gitea.com` addresses. Adding
`- matchName: dl.gitea.com` to the same egress rule makes `helm repo add`
succeed in under a second, where it previously timed out at 121s.

### Two things that made this look unsolved for longer than it was

Both are worth remembering, because each produced a confident wrong conclusion.

**The FQDN cache check queried the wrong agent.** `cilium-dbg fqdn cache list`
returned nothing for gitea, which suggested Cilium was never observing the DNS
responses and so could permit no IPs. That check ran against the control-plane
agent. `argocd-repo-server` runs on `kind-local-worker`, and on *that* agent the
cache holds both names correctly:

```text
680   lookup   dl.gitea.io.    30   104.21.17.32,172.67.220.34
680   lookup   dl.gitea.com.   30   104.26.3.246,104.26.2.246,172.67.75.17
```

Endpoint 680 is repo-server. DNS observation was working the whole time. Always
exec the agent on the node the workload is scheduled to.

**The correct fix was tried and wrongly recorded as "did not fix it."** The
2026-08-13 session added `dl.gitea.com`, tested, still saw the 121s timeout, and
concluded the change was necessary-but-not-sufficient. Re-running the same edit
on 2026-08-14 fixed it immediately. The likely cause of the false negative is
the self-heal gotcha below reverting the policy before the test landed. Treat a
negative result here as unreliable unless the live CCNP was re-read *after* the
test, not just after the apply:

```shell
kubectl get ccnp argocd-repo-server-helm-egress -o jsonpath='{.spec.egress[*].toFQDNs}'
```

### Applying it

`kubectl apply` alone does not persist: `cilium-policies` has `selfHeal: true`
and reverts within seconds. The durable path is `tofu apply`, which re-renders
the policies repo and retriggers the `sync-gitea-policies.sh` null_resource via
`repo_render_hash` in `gitops.tf`. For a live test only, pause and restore:

```shell
kubectl -n argocd patch applications.argoproj.io cilium-policies --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl apply --server-side --force-conflicts -f <policy file>
# ... test ...
kubectl -n argocd patch applications.argoproj.io cilium-policies --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

The working tree carries the policy edit. It has **not** been pushed to the
Gitea policies repo, so the live cluster is back to the pre-fix allowlist:

```text
$ kubectl get ccnp argocd-repo-server-helm-egress -o jsonpath='{.spec.egress[*].toFQDNs}'
[{"matchName":"dl.gitea.io"}]
```

### Do not read the live Application status as evidence here

After the test above, `gitea` reads `sync=Synced, health=Healthy` **despite**
the allowlist having reverted. The successful fetch during the test populated
the repo-server's helm cache, so manifest generation now succeeds from cache
and never re-resolves the host.

That is a cached success on top of an unfixed policy. It will hold until the
cache is evicted or the repo-server restarts, and then the 121s timeout and
`sync=Unknown` return. A green `gitea` row is therefore not evidence the fix
landed; the only reliable check is the CCNP contents above. This is very
likely the same trap that made the 2026-08-13 result confusing in the first
place, in the opposite direction.

### Landed 2026-08-14

`tofu apply` at stage 900 put the policy in the cluster. Verified against the
live cluster rather than the Application row:

```text
$ kubectl get ccnp argocd-repo-server-helm-egress -o jsonpath='{.spec.egress[*].toFQDNs}'
[{"matchName":"dl.gitea.io"},{"matchName":"dl.gitea.com"}]

$ terraform/kubernetes/scripts/check-policy-drift.sh --execute
OK   all 32 Cilium policies match the rendered source
```

The cached-success caveat above does not apply to this result. The apply
replaced `null_resource.argocd_repo_server_restart`, so the repo-server
restarted (14:34:42Z) and its Helm cache was discarded. `helm repo add` inside
the fresh pod now completes in under a second, where it previously timed out at
121s, so the fetch is genuinely re-resolving `dl.gitea.com` rather than reading
a warm index. `gitea` is `Synced/Healthy` on a policy that actually permits the
fetch.

Section 4 is closed.

## 5. Two Sources Of Truth For Tool Pins

`install-tool-hints.sh` derives pins from `.devcontainer/toolchain-versions.sh`,
so hints track bumps automatically — confirmed when terragrunt moved to `1.1.2`.
The committed `mise.toml` is hand-written and will silently go stale the moment
`update-versions.sh --apply` moves a pin.

Either generate `mise.toml` from `toolchain-versions.sh` behind a make target, or
add a drift assertion to `.devcontainer/check-toolchain-surface.sh`, which
already guards that surface.

Done on 2026-08-13 with the drift assertion rather than generation, so
`mise.toml` stays a file an operator can read and edit. `check_mise_pin_drift`
compares every pin the two files share, normalising the leading `v` that
`toolchain-versions.sh` carries and `mise.toml` omits. Pins with no devcontainer
equivalent are reported but not failed, so `mise.toml` can still carry host-only
tools.

## 6. Charts Can Never Be Bumped

`update-versions.sh --only charts` returns `deployed_unavailable` for all twelve
components, so nothing is ever eligible and `--apply` skips everything. Updates
are genuinely available:

| Chart | Pinned | Available |
| --- | --- | --- |
| argo-cd | 10.2.1 | 10.3.0 |
| prometheus | 29.20.0 | 29.21.0 |
| otel-collector | 0.165.0 | 0.166.0 |

Determined and fixed on 2026-08-13, and the framing of "when no cluster is
present" was too generous. `update-versions.sh` always invokes
`check-component-version.sh --execute --ci`, and `--ci` forces `CLUSTER_OK=0`,
which sets all twelve `DEPLOYED_*` values to `Unavailable`. The deployed read was
therefore never going to succeed for the charts domain on any host, cluster or
not.

`component_status_code` tested `deployed == "Unavailable"` before it tested for
an available update, so that branch swallowed every row. It now degrades to a
version-only comparison: a codebase pin behind upstream reports
`update_available`, and `deployed_unavailable` is reserved for rows where there
is genuinely nothing to say. Verified against this document's own table:

```text
argo-cd chart    10.2.1   10.3.0   update available
otel-collector   0.165.0  0.168.0  update available
prometheus chart 29.20.0  29.21.0  update available
```

## 7. Backstage Is Outside The Supply-Chain Policy

The packages domain reports `lockfile_missing_or_unverified` for roughly sixty
`@backstage/*` and related packages under `apps/backstage/packages/{app,backend}`.
None of it can be version-checked or cooldown-gated, so the policy enforced
everywhere else does not cover the largest JS dependency tree in the repo.
`apps/backstage/.yarn/releases/yarn-4.4.1.cjs` is also a large vendored binary
in-tree.

Backstage is now opt-in and grouped with the APIM simulator: `enable_backstage`
defaults to `false` like `enable_apim_simulator`, and both Launchpad tiles are
gated behind `ENABLE_BACKSTAGE`. Remaining options for the dependency tree
itself: repair the lockfile so it can be audited, extract Backstage to its own
repository, or drop it.

### Resolved 2026-08-14: the lockfile was never broken

Decision taken: repair the lockfile so the tree can be audited, keeping
Backstage in-repo. It turned out there was nothing wrong with the lockfile.

`apps/backstage/yarn.lock` is a valid 1.2MB Yarn Berry v8 lockfile. The audit
could not read it for two independent reasons, both in
`check-component-version.sh` rather than in Backstage:

1. **Only `bun.lock` was understood.** `emit_js_dependency_rows_for_package_json`
   called `bun_lock_resolved_version` and nothing else, so a Yarn Berry
   lockfile resolved no versions at all.
2. **The lookup never left the package directory.** It resolved
   `<dirname package.json>/bun.lock`. Backstage is a Yarn *workspace*
   (`packages/*`, `plugins/*`), and workspace members carry a `package.json`
   but no lockfile of their own — the single resolved lockfile is at the
   workspace root. Fixing only (1) would still have missed
   `packages/{app,backend}`, which is where the ~60 reported packages live.

`lockfile missing or unverified` is emitted whenever `current` comes back
empty, so both faults presented identically and neither pointed at its cause.

The fix adds `yarn_lock_resolved_version` (Yarn Berry format, handling the
comma-separated multi-spec entry keys) and `js_lock_resolved_version`, which
tries `bun.lock` then `yarn.lock` and walks up towards `REPO_ROOT`, stopping at
the boundary so a lookup can never pick up a lockfile outside the repository.

Result across `apps/backstage` and both workspace members:

```text
direct deps checked: 81
now resolved:        81
still unresolved:   none
```

All 81 are now version-checked and cooldown-gated like every other dependency,
so the policy covers the largest JS tree in the repo. Covered by three tests in
`kubernetes/kind/tests/check-version.bats`, including a prefix-collision case
(`prefix` must not match `prefix-collide`) and the repo-root boundary.

Two things this does **not** do, both still open if you want them:

- `apps/backstage/.yarn/releases/yarn-4.4.1.cjs` is still a large vendored
  binary in-tree. That is a separate question from auditability.
- Extraction and removal remain available. This closes the audit gap, which was
  the reason the section existed, but it does not settle what the repo is for.

## 8. Substrate Strategy

`kubernetes/docker-desktop/` is an entire substrate named after a macOS-centric
runtime, with its own tfvars, preload list and scripts. `docs/STATUS.md` already
records Slicer removed and Lima demoted to best-effort; docker-desktop may
warrant the same call now the primary host is Linux.

Slicer is removed but remnants persist:

- competing-VM classification in `check-memory-preflight.sh`
- three bats fixtures containing `/Users/nick/slicer-mac` paths
- absence assertions in `check-devcontainer-version.sh` and
  `check-toolchain-surface.sh`
- references in `docs/STATUS.md`

Note the operator has a `slicer` binary installed on the Linux host, so confirm
intent before purging rather than assuming the removal still stands.

### Decided 2026-08-14: keep both, change nothing

Operator's call on both parts: `kubernetes/docker-desktop/` stays, and the
Slicer remnants stay. No code moves.

This closes the section as a decision, not as an implementation. The remnants
listed above are inert, and leaving them costs nothing beyond the confusion of
reading them, so revisit only if that confusion actually bites. Do not treat
the remnants as evidence of intent in future passes: they persist because
removing them was declined, not because it was overlooked.

## 9. Repo Hygiene And Onboarding

All four done on 2026-08-13.

- The empty tracked `cp` file at the repo root, committed in #164 as a mistyped
  `cp .env.example .env`, is removed.
- `.playwright-mcp/` was already in `.gitignore`, but its twenty-odd console and
  page logs from 2026-04-27 were still tracked, which is why the ignore rule had
  no effect. They are untracked now and remain on disk.
- `.skill-loop-progress.md` is untracked and added to `.gitignore`.
- `make init-env` writes `.env` from `.env.example` and generates
  `OAUTH2_PROXY_COOKIE_SECRET` along with the two demo passwords, which were the
  same trap one step further on. It never overwrites a value that is already
  set, so it is safe to re-run against a configured `.env`, and it fills only
  keys that are present but empty. The README now points at it instead of
  `cp .env.example .env`.

### Correction 2026-08-14: `cp` had a generator, and it is still in the tree

The removal above would not have held. `cp` reappeared at the repo root during
this session, and `make test-ci` recreates it on every run — so the staged
deletion was being silently undone.

The cause is not the #164 typo but a stray line continuation in
`kubernetes/kind/tests/sync-gitea-policies.bats`. A `touch` argument list ended
with a trailing `\`, so it swallowed the following `cp` command:

```bash
    "${stack_dir}/apps/.../referencegrant-hubble.yaml" \
  cp "${stack_dir}/apps/platform-gateway-routes/httproute-agentgateway-ai-gateway.yaml" \
    "${stack_dir}/apps/.../httproute-agentgateway-ai-gateway.yaml"
```

Bash read that as `touch <7 paths> cp <src> <dst>`. Two consequences, only the
first of which was visible:

- an empty file named `cp` was created in the working directory, which is the
  repo root
- **the copy never ran.** The SSO `httproute-agentgateway-ai-gateway.yaml` was
  being created empty by `touch` rather than copied, so the fixture that two
  agentgateway tests render against was not the file the test claims to set up

The suite passed either way, which is why it went unnoticed — the assertions
never depended on that file's contents. Fixed by deleting the trailing
backslash; `sync-gitea-policies.bats` is 47/47 and no longer leaves a stray
`cp` behind.

Worth noting for section 1: this is a case the safety net could not catch,
because the defect was *in* the safety net and its only outward symptom was an
untracked file nobody attributed to a test.

## 10. Credential Hygiene On Linux

`docker login` on Linux with no credential helper stores base64 credentials in
plaintext in `~/.docker/config.json`. `dhi-creds-offline.sh` already anticipates
a file-backed helper; the Linux equivalent is
`docker-credential-secretservice` or `docker-credential-pass`, and the
prerequisites documentation should say so.

Documented on 2026-08-13 in `kubernetes/kind/README.md`, which previously
covered only the macOS and Docker Desktop side of this. Both the Linux helper
options and the `dhi.io` account facts below are now recorded there.

Worth recording, because it cost real time: **`dhi.io` authenticates with an
ordinary Docker Hub account.** There is no separate registration and no paid
tier for the core images. A `docker login dhi.io` failure is almost always
either a missing `dhi.io` entry in `config.json` or a password being used where
the account requires a personal access token.

## 11. The Host Alias Does Not Survive A Restart

Found on 2026-08-13 while confirming the cluster state above, and it is the
first table row showing up again in a new place.

The stage 900 cluster was up but degraded: 77 pods Running and 12 in
`ImagePullBackOff`, every one of them pulling from
`host.docker.internal:5002`. Inside the nodes the name did not resolve at all:

```text
$ docker exec kind-local-control-plane getent hosts host.docker.internal
(no output)
```

`ensure-node-host-alias.sh` exists for exactly this and works correctly. The gap
is when it runs. It is wired into `plan`, `apply` and `start-kind`, but the node
containers had been restarted outside those paths (containers up 8 minutes,
nodes 28 hours old), and a kind node's `/etc/hosts` does not survive a container
restart. Nothing re-applied the alias, and nothing reported it either:
`make status` showed the cluster running.

Running the existing target repaired it, and the cluster returned to the
baseline recorded at the top of this document:

```shell
make -C kubernetes/kind ensure-node-host-alias
# OK   host.docker.internal -> 172.18.0.1 added to 2 kind node(s)
# 89 pods Running, zero unhealthy
```

So the fix is only a question of where to call it. Options, cheapest first:

- call it from `prereqs`, which operators already run first, and which the
  script is designed for: it is idempotent and a no-op on Docker Desktop
- have `check-health` report an unresolvable alias instead of leaving the
  failure to show up as twelve unexplained `ImagePullBackOff` pods

Not done here, because it changes what a target does rather than fixing a
defect, and the wiring choice is a judgement call about which target owns this.

### Second occurrence, 2026-08-14

Reproduced by a host reboot, without any `make` target involved. Both node
containers came back up with the alias gone:

```text
$ docker exec kind-local-control-plane getent hosts host.docker.internal
(no output)      # same for kind-local-worker
```

`make -C kubernetes/kind ensure-node-host-alias` repaired it again. Two points
this adds to the case above:

- the trigger is a plain host reboot, which no operator would think of as a
  cluster operation, so no existing entry path is crossed on the way back up
- it recurs. This is not a one-off from an unusual container restart, it is the
  steady-state behaviour of a kind node's `/etc/hosts` across any restart

That makes the `prereqs` option the stronger of the two, and the `check-health`
report worth having regardless: on this occasion the alias was gone *before*
any workload noticed, and `make status` would again have reported the cluster
as running.

### Implemented 2026-08-14: both options, split by intent

Repair and reporting are deliberately separate targets, because a diagnostic
that silently mutates the cluster it is inspecting is worse than the bug.

- `ensure-node-host-alias.sh` gains `--check`: reports per node, never writes,
  exits 0 either way. It bypasses the `--execute` confirmation gate, which
  exists to guard writes it does not perform.
- `prereqs` calls `ensure-node-host-alias` (repair) after `ensure-kind-running`,
  once the cluster is known up.
- `check-health` calls the new `check-node-host-alias` target (report only),
  which names the problem and prints the repair command:

```text
OK   host.docker.internal already resolves in 1 kind node(s)
WARN host.docker.internal does not resolve in 1 kind node(s); images referencing it cannot be pulled
WARN repair: make -C kubernetes/kind ensure-node-host-alias
```

Verified against the live cluster by deleting the alias from one node, running
the report (which flagged it and left the node untouched), then repairing.
Covered by `kubernetes/kind/tests/ensure-node-host-alias.bats`, which had no
tests before this.

Note `/etc/hosts` in a kind node is a bind mount, so `sed -i` fails with
`Device or resource busy`. Rewrite it in place instead:

```shell
docker exec <node> sh -c "grep -v host.docker.internal /etc/hosts > /tmp/h && cat /tmp/h > /etc/hosts"
```

## 12. `make -n` Is Not A Dry Run Here

Found on 2026-08-14 by running it and applying the stack by accident.

`make -C kubernetes/kind --just-print 900 apply AUTO_APPROVE=1` performs a real
apply. It took the state lock, ran to completion, and failed a concurrent
operator-initiated apply with:

```text
Error: Error acquiring the state lock
Operation: OperationTypeApply
Who:       nick@L450
```

This is documented GNU make behaviour, not a bug in make. From the manual, on
`-n`, `-t` and `-q`:

> the `-n`, `-t`, and `-q` options do not affect recipe lines that begin with
> `+` characters or contain the strings `$(MAKE)` or `${MAKE}`.

The `apply` recipe is a single backslash-continued shell block, and that block
contains `$(MAKE)` in four places (`check-platform-env`, a nested
`apply STAGE=100`, `check-kind-host-ports`, `ensure-image-cache`). Make treats
the whole continued block as one recipe line, sees `$(MAKE)` in it, and exempts
the entire thing from `-n`. Everything else in the block — including the
terragrunt invocation — executes for real.

`plan` has the same shape, so the same applies there.

The consequence worth stating plainly: the one command an operator would reach
for to preview a destructive target is the command that performs it, and it
gives no warning that it did.

Not fixed here, because the options differ in what they change:

- move the terragrunt invocation behind its own `$(MAKE)` sub-target, so the
  block containing it no longer needs `$(MAKE)` inline and `-n` behaves
- add an explicit `preview` target that is honestly read-only, and have the
  Makefile refuse `--just-print` on `plan`/`apply` with a message pointing at it
- leave it and document it, on the grounds that `plan` already exists as the
  intended preview path

The second is the smallest change that removes the sharp edge. The first is the
correct one. This needs a decision, not an implementation.

## 13. Two CI Failures That Predate This Branch

Found on 2026-08-14 while checking whether PR #196 was ready to merge. Not
caused by it, and not fixed by it.

`main` is red. A `workflow_dispatch` run of `ci.yml` against `main`
(run 31814946743) fails four tests in the hermetic bats subset:

```text
not ok 222 root status supports json output without requiring platform env
not ok 234 docker compose prereqs fails cleanly when the repo env file is missing
not ok 266 the reference variant owns the machine when kind is serving traffic
not ok 288 sentiment prereqs fails cleanly when the repo env file is missing
```

The branch for #196 fails only the middle pair, so it reduces the count from
four to two rather than adding any. That is the reason it was proposed for
merge with CI red.

### The two that remain

Both assert the same thing in different Makefiles:

- `tests/makefile.bats:458` (docker compose)
- `tests/sentiment-makefile.bats:49` (sentiment)

Each runs the target with `PLATFORM_ENV_FILE` pointed at a file that does not
exist, and expects the failure to name it:

```bash
[[ "${output}" == *"Missing platform env file:"*"/missing.env"* ]]
```

The exit status assertion on the preceding line passes, so the target does fail
— it just fails without that message. The shared signature across two unrelated
Makefiles suggests one root cause, not two.

### What has already been ruled out

- **Not a regression from this branch.** `mk/common.mk`, which owns the
  message, is unchanged since PR #126. Neither test file was touched.
- **Not target ordering.** `prereqs` calls `check-platform-env` first in both
  Makefiles, so the env check runs before the docker and mkcert checks.
- **Not the missing host tooling.** Reproduced locally with `env -i` and a PATH
  containing only coreutils, without `docker` or `mkcert`: the message still
  appears and the test still passes.
- **Not a stale `.env`.** The tests pass an explicit path, and the conditional
  `include` in `docker/compose/Makefile` is guarded by `wildcard`.

### Root cause: the recipe shell was never Bash

Resolved on 2026-08-14. Everything above was true and none of it was the cause.

The captured output was the thing that settled it. Diagnostics were pushed on a
branch, `ci.yml` was dispatched against it, and the runner printed this:

```text
make[1]: Entering directory '/home/runner/work/platform/platform/docker/compose'
/bin/sh: 1: set: Illegal option -o pipefail
make[2]: *** [../../mk/common.mk:62: check-platform-env-file] Error 2
make[1]: *** [Makefile:33: prereqs] Error 2
```

Alongside it, `/bin/sh -> /usr/bin/dash` and `SHELL = /bin/sh`.

`mk/common.mk` opened with `SHELL ?= /bin/bash`. That line never did anything.
`?=` assigns only when a variable is undefined, and GNU make always has a
`SHELL` defined — `$(origin SHELL)` reports `file`, not `undefined`, even in a
makefile that never mentions it. So every Makefile including `mk/common.mk` ran
its recipes under `/bin/sh`, and `check-platform-env-file` opens with
`set -euo pipefail` and goes on to use arrays and `$${!name-}`.

On Arch, `/bin/sh` is a symlink to Bash, so all of that works and the test
passes. On Debian and Ubuntu — which is what `ubuntu-latest` is — `/bin/sh` is
dash. dash has no `pipefail`, and an invalid option to a special builtin aborts
the shell, so the recipe died on its first line. That is why the exit-status
assertion passed while the message assertion did not: the target genuinely
failed, just for a completely different reason than the test was describing.

The blast radius was narrow only by luck. `SHELL := /bin/bash` was already
spelled correctly in the root, kind, lima, devcontainer, sites/docs and
experiments Makefiles; `mk/common.mk` was the single file using `?=`, and it is
the include behind `docker/compose/Makefile` and every `apps/*/Makefile`.

The fix is one character class: `SHELL := /bin/bash`. Two guards were added in
`tests/makefile.bats` so the shape cannot come back — one asserting that a
makefile including `mk/common.mk` gets a Bash recipe shell that accepts
`pipefail`, and one asserting that no tracked makefile assigns `SHELL` with
`?=` at all, since that assignment is always a silent no-op.

This is section 1's lesson again, in its purest form: the hermetic test was
reading host state, and the piece it was reading was what `/bin/sh` points at.
A test that only ever runs on the machine that writes the code cannot see it.

### The other two, and the two that replaced them

The first and third failures on `main` (`root status supports json output` and
`the reference variant owns the machine`) were fixed by #196 and are green.

By the time this branch was cut, a different pair had gone red on `main`:

```text
not ok 108 CI workflow pins GitHub Actions and runs lint plus hermetic Bats
not ok 341 version audit workflow pins GitHub Actions by SHA and runs lightweight audits
```

Dependabot's `actions/checkout` bump to v7.0.1 (#193) rewrote the pin in
`version-audit.yml`, `release.yml` and one of the two occurrences in `ci.yml`,
but not the second occurrence — the `macos-latest` job, which PR #196 added
after the Dependabot branch was cut — and not the expected SHAs restated
inside `tests/ci-workflow.bats`, `tests/version-audit-workflow.bats` and
`tests/release-workflow.bats`. All five were brought to v7.0.1 here.

Those tests assert the exact pin rather than merely that one exists, which is
the right shape — it is what stops an unpinned action being added quietly to
the workflow that audits supply-chain versions. The cost is that a Dependabot
bump is only ever half a change until the tests move with it, and Dependabot
cannot make that half. Expect this to recur on the next bump.

### A gap this exposed: not every workflow test is in the gate

`tests/release-workflow.bats` was red for the same reason and nothing caught
it, because it is **not listed in `CI_BATS_TESTS` in the root `Makefile`**. It
is fixed here, but it will drift red again unnoticed, and so will anything else
added to `tests/` without being added to that list.

Adding it is a one-line change, deliberately left out of the change that found
it to keep that one reviewable. The broader question is worth asking with it:
`CI_BATS_TESTS` is a hand-maintained list, so a new test file is outside the
gate until someone remembers. An assertion that every `tests/*.bats` file is
either listed or explicitly excluded would close the class rather than this one
instance. That is section 1's thesis applied to the gate itself.

That `main` is red at all belongs to section 1's thesis rather than this
section's. The gate exists, it runs, and nobody is looking at the result.

## 14. Recursive Make Noise In The Kind Stage Ladder

Done on 2026-08-14.

`kubernetes/kind/Makefile` now sets `MAKEFLAGS += --no-print-directory`. `apply`
chains about fifteen recursive `$(MAKE)` calls and `prereqs` nests more, so a
stage run was mostly `Entering directory` / `Leaving directory` with the real
output threaded through it.

The evidence that this is safe was already in the tree. Six test files were
passing `--no-print-directory` at individual call sites purely to work around
these lines, three of them with a comment saying so; section 1 records four test
failures the lines caused; and nothing anywhere asserts that they are present.
Setting it once in `MAKEFLAGS` also covers the sub-makes, which a per-call-site
flag does not.

The per-call-site workarounds are left in place. They are now redundant rather
than wrong, and retiring them is a separate change that would touch six test
files for no behavioural gain.

The root `Makefile` was considered and deliberately left alone: every `$(MAKE)`
in it already passes `--no-print-directory` explicitly, so there is nothing for
the flag to fix there.
