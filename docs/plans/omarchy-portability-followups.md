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

### Resolved 2026-08-14: refuse, and stop the exemption reaching terragrunt

Both options taken. The refusal is the load-bearing one, for a reason that only
became clear while implementing it.

**The refusal has to happen at parse time.** A guard written as a recipe line
would itself be skipped under `-n` -- the very trap being guarded. So it is a
`$(error)` evaluated while the makefile is read:

```make
KIND_DRY_RUN_REQUESTED := $(findstring n,$(firstword -$(MAKEFLAGS)))
ifneq ($(KIND_DRY_RUN_REQUESTED),)
ifneq ($(filter plan apply,$(MAKECMDGOALS)),)
$(error make -n/--just-print is unsafe for ...)
endif
endif
```

Verified: `make -C kubernetes/kind --just-print 900 apply` and the same for
`plan` now abort before any recipe runs. `--just-print` on other targets still
works, and normal `plan`/`apply` are untouched.

**Why the restructure alone would not have been enough.** The obvious fix is to
move the terragrunt call behind its own sub-target so that, under `-n`, make
recurses but the leaf recipe is printed rather than run. That does protect
terragrunt. It does not make `-n` a preview, because the same exemption applies
to every other `$(MAKE)` line in the block: `prepare-state`,
`render-operator-overrides`, `prereqs`, `ensure-image-cache` and
`preload-images` all still execute for real. `-n` on this target can never mean
"no side effects" while the recipe is built from recursive make.

That is the case for refusing outright rather than making `-n` partially safe,
and it is why the refusal came first.

The guard is covered by a test in `kubernetes/kind/tests/makefile.bats`, and
that test is deliberately static. Asserting the behaviour would mean running
`make -n apply` to observe the refusal, which performs a real stage apply if the
guard ever regresses. A test whose failure mode is "applies the operator's
cluster" is not worth the extra fidelity.

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

## 15. The CI Gate Is Hand-Maintained

Found on 2026-08-14 after `tests/release-workflow.bats` was discovered red with
nothing watching it. It had never been added to `CI_BATS_TESTS`.

The instance is minor. The class is not: **37 of the 99 `tests/*.bats` files are
outside the gate.** A new test file runs only if someone remembers to list it,
and nothing says otherwise, so the cost of forgetting is silent.

`tests/ci-test-gate.bats` now asserts the list is complete, and a second case
asserts it names no file that has since been deleted.

The 37 pre-existing files are recorded in the test as a named backlog rather
than being added wholesale. Adding them blind would import an unknown number of
failures and an unknown amount of runtime into the gate, and several are the
kind that read host state -- exactly the class section 1 documents. Each needs
checking before it joins the hermetic subset.

So this is a ratchet, not a fix: the gap is now visible, reviewable, and cannot
grow. Verified by adding a new test file and watching the guard fail, then
removing it.

### Burning the backlog down, 2026-08-14: 37 to 26

Each of the 30 safe-to-run files was executed in isolation. **11 passed and are
now in the gate. 19 failed.** The remaining seven were left untriaged because
they reference `docker build`/`run`/`compose`, and running them unsupervised
risks real side effects.

That is the finding worth recording: the backlog was never merely a listing
oversight. Two thirds of it is **red**, from one failure in most files to 15 in
`tests/vanilla-js-typecheck.bats`. Adding them to `CI_BATS_TESTS` unfixed would
simply move the redness into the gate, which is the condition this whole effort
exists to end. Each remaining file needs its failures fixed before it joins, and
the counts are recorded beside the backlog entries so the size of that job is
known rather than guessed.

`tests/release-workflow.bats` -- the file whose silent redness started section
15 -- passed and is now guarded.

### Closing the gap immediately found more of the section 13 bug

`tests/langfuse-demos.bats` passed locally and failed in CI on:

```text
/bin/sh: 1: set: Illegal option -o pipefail
```

That is the section 13 defect again. The fix there pinned `SHELL := /bin/bash`
in `mk/common.mk`, but `mk/go-app-core.mk` pinned nothing at all, so the **eight
app Makefiles that include it** were running recipes under `/bin/sh` the whole
time. Bash on Arch, dash on the runner, so it could only ever be seen in CI --
and the tests that would have seen it were the ones outside the gate.

The gap was hiding instances of the bug the gate was fixed to catch. That is the
clearest argument in this document for closing it.

The guard from section 13 did not catch this, because it only banned
`SHELL ?=`, the assignment that never fires. It said nothing about pinning no
`SHELL` at all, which fails identically. A second guard now checks each
top-level Makefile and its direct includes: if anything in that chain uses Bash
syntax, something in it must pin `SHELL :=`. Verified by removing the pin from
`mk/go-app-core.mk` and watching it fail.

### The gate had an assertion requiring the gap

Adding the 11 broke `root test-ci delegates to the explicit hermetic Bats
subset`, which asserted that `tests/app-healthcheck-commands.bats` and
`tests/release-workflow.bats` were **absent** from `CI_BATS_TESTS`.

So a test required the exclusion of the very file whose exclusion let it go red
unnoticed. This is the same shape as section 1's discovery that
`tests/ci-workflow.bats` asserted `pull_request` and `push` were absent from
`ci.yml`: an assertion that encodes the defect, with no recorded reason, and
which therefore defends it. The absence checks now carry a comment saying they
exist to prove the subset is an explicit list rather than a glob, and that a
name should be removed when its file joins the gate.

### Burning it down further, 2026-08-15: 26 to 21

Five more files joined the gate. The counts the previous pass claimed to have
recorded were not actually written down, so every safe-to-run file was re-run in
isolation and its real fail/total is now in `tests/ci-test-gate.bats`. 16 of the
20 are red, the worst being `vanilla-js-typecheck` at 15/61.

Two of the four green additions were merely unlisted. The other two were red for
reasons worth stating.

**A policy test that could never pass.** `tests/python-wrapper-policy.bats`
greps the tree for `python3` and fails on any hit outside an allowlist. The grep
line itself contains the string, and the file was not in its own allowlist, so
it failed on every tree since #68 — a test with no passing input, invisible
because it sat outside the gate. Its allowlist had also rotted **in both
directions**: six entries permitted nothing at all, while ten tracked files used
`python3` with four named. It now excludes itself by pathspec, and a second test
asserts no allowlist entry has gone dead.

That second assertion is the general lesson. An allowlist is normally guarded
only against being too small; nothing notices when it grows permissions for
files that no longer need them, and a stale entry is an unreviewed permission.

**A scanner blind to dotfiles.** `tests/subnetcalc-naming.bats` used `rg`, which
skips hidden files by default, so it could not see dot-directories at all. It
also needed six globs to talk itself out of `node_modules` and `dist`, none of
which are tracked. Switching to `git grep` over tracked files removed the globs,
removed the dependency on `rg` being installed, and immediately surfaced two
genuine stale references the old scan had never been capable of seeing: a
`.yamllint` ignore for `apps/subnet-calculator/apim-simulator/`, a path that has
not existed since the rename and was matching nothing, and
`apps/subnetcalc/.gitea/workflows/build-images.yaml` still titled
`Build subnet-calculator images` with `WORKDIR: /tmp/subnet-calculator`.

`kubernetes/kind/tests/app-repo-sync.bats` already banned `subnet-calculator.git`
in that exact workflow file and passed the whole time. The assertion was narrower
than the class it was meant to enforce.

### A backlog test was deleting the operator's real cache

The most serious finding, and it argues for triaging these files rather than
adding them blind.

`tests/reset-local-state.bats` builds a fixture HOME and runs
`reset-local-state.sh --execute --include-host-caches` against it. The script
locates the uv cache by running `uv cache dir` — and **`uv` ignores a reassigned
`HOME`**, returning the invoking user's real cache instead. So the test deleted
`~/.cache/uv` on this host rather than its fixture. Observed directly:

```text
$ ls /home/nick/.cache/uv
ls: cannot access '/home/nick/.cache/uv': No such file or directory
```

Only a cache, and uv repopulates it, but the sandbox was not a sandbox. uv was
the single host cache resolved *only* by asking the tool; `playwright` and `pip`
already fell back to `${HOME}`-derived candidates and were never exposed. uv now
uses that same shape.

The per-call fix is not the real one. `append_host_cache_path` now enforces
containment centrally: a host cache resolving outside `HOME` is skipped with a
warning and never removed, so the next tool that ignores `HOME` cannot widen the
blast radius again. Verified by pointing the override outside `HOME` and
asserting the file survives.

Worth carrying forward: **a test that sets `HOME` has not sandboxed anything.**
It has only sandboxed the tools that read `HOME`, and which those are is not
knowable from the test.

### The 1Password signing trap, twice

Both `release-script.bats` and `reset-local-state.bats` build fixture git repos
and commit into them. A fixture repo inherits global config, so a host with
`commit.gpgsign = true` sends every fixture commit to that signer:

```text
error: 1Password: failed to fill whole buffer
fatal: failed to write commit object
```

CI has no signing configured, so this passes there and fails only on a developer
workstation — section 1's one-direction host dependence again, pointing the
opposite way from the usual case. `git-hooks.bats` and
`check-worktree-unchanged.bats` already pin `commit.gpgsign false`; the idiom
existed and two files had simply not adopted it. Both now do.

### The absence assertion, third instance

`tests/makefile.bats` asserted `tests/release-script.bats` was **absent** from
`CI_BATS_TESTS`. The comment added on 2026-08-14 says to remove a name when its
file joins the gate, so it was removed. Recording it because it is now a
reliable pattern rather than a coincidence: each time a file joins the gate,
check what asserted its absence.

### What is left, and what it needs

21 files. Two of them are not assertion fixes:

- `grafana-dashboard-quality` (2/4) asserts that live Prometheus queries return
  series. It cannot be hermetic in its present shape and needs either a recorded
  fixture or a decision that it is a cluster test rather than a gate test.
- `platform-workflow-ui` (2/11) does not fail so much as never finish; it was
  killed at 300s. A hanging test in a gate is worse than a red one.

Six are untriaged because they drive `docker build`/`run`/compose. Given what
`reset-local-state` turned out to be doing to the host, those should be run
deliberately and watched, not swept in.

### 21 to 16, and one refactor accounts for three of them

Five more added. The pattern in this batch is different from the last one: these
were not tests that had rotted slowly, they were tests left behind by a single
change.

**PR #126 broke three of them and nothing said so.** That refactor moved the
Kubernetes and build plumbing around, and three suites still asserted the shapes
it replaced:

- `kubernetes-stage-helper-surface` asserted the diagnostic runner is invoked
  with `--show-urls`. #126 created `run-diagnostic-check.sh`, which has only ever
  taken `--action show-urls`, and created this test in the same commit. It was
  **born red** and has never passed on any tree.
- `sso-e2e-app-toggles` asserted the kind Makefile contains
  `STAGE_TFVARS_FILES="$$tfvar_files_joined"`. #126 moved that layering into
  `build-sso-e2e-env.sh`; the local variable has not existed since.
- `local-idp-container-images` asserted an inline
  `GOOS=linux GOARCH=$${GOARCH:-$(IDP_GOARCH)}` in the idp-core app Makefile.
  #126 moved the build line into `mk/go-app-core.mk`, where it now reads
  `GO_APP_GOARCH`. The behaviour is intact; only the assertion was stranded.

A refactor that lands with three of its tests asserting the old code is what
"outside the gate" costs, stated as a number. None of these were subtle, and any
one CI run would have caught all three.

**A policy assertion that could not see the thing it guards.**
`kubernetes-mcp-manifests` checks which workloads may reach the MCP namespace. It
compared two sets: source *names*, collected only from endpoints carrying
`k8s:app.kubernetes.io/name`, and source *namespaces*. PR #189 added a rule
letting `dev`/`langfuse-demos` reach `platform-mcp` on 8080 — selected by
`part-of`, not `name` — so the name set never saw it, and only the namespace set
noticed. A source could have been added under any other label key and been
invisible to both.

The rule itself is legitimate and merged; the test was simply not updated,
because it does not run. It now compares the full ingress surface as exact
`(ports, selector)` pairs, so a new source is either listed or the test fails.
For a policy guard, "the sets I happened to collect match" is not the same
assertion as "this is the entire surface".

**`subnetcalc-go-only`** was the locale-collation trap from section 1 again,
plus real drift: `edge/` and `update-subnetcalc-image-tags.sh` are canonical —
`sentiment` carries the same pair — and arrived in #111 and #113 without this
list following.

### The new guards immediately caught their own author

Appending the previous section to this document turned both policy tests red:
it names `python3` and `subnet-calculator` in order to describe them. That is
the guards working, but it also showed the allowlists were the wrong shape.
Prose and recorded artifacts are not host-side code and are not renameable
source, so `docs/` (python) and `docs/adr/`, `docs/plans/` (naming) are now
scan-level prefix exemptions rather than per-file allowlist entries. Prefixes
are deliberately not dead-checked: a document may stop mentioning something
without that being a finding, whereas a code path that stops needing an
exception is a live permission nobody reviewed.

### 16 to 9: auth-chat was never registered anywhere

Seven more added, and the batch has a single dominant theme: an application
that exists, deploys, and serves traffic, but which none of the repo's registries
knew about.

`auth-chat` has carried `apps/auth-chat/app/go.mod` since it was added. It was
missing from **five** separate places:

- `canonical_go_app_names()`, while `discovered_go_app_names()` found it on the
  filesystem. `app-layout-consistency` asserts those two are equal, which is
  exactly the check designed to catch this, and it had been failing unwatched.
- the Backstage production catalog (`apps/backstage/catalog/apps/auth-chat/`),
  though `apps/auth-chat/catalog-info.yaml` existed and was correct
- both Backstage `app-config` location lists, dev and production
- `catalogMetrics.ts`, so it was outside catalog observability
- the ubiquitous language service-surface paragraph in `docs/ddd/`

Its wrapper Makefile also declared `prereqs` in `MAKE_KNOWN_GOALS` with no rule
anywhere defining it, and `build:` depended on that non-existent target. It only
appeared to work because an unmatched prerequisite with no recipe is inert.
`auth-chat` now follows `langfuse-demos`, the other app with no `compose.yml`:
`app-prereqs` in the wrapper delegating to a real `prereqs` in the app Makefile.

One application, five registries, and every contract meant to notice was in the
backlog. This is the clearest case yet that the gate's value is not the tests it
contains but the ones it does not.

### Two more tests that could never have passed

- `app-layout-consistency` asserts a fixture wrapper's help output does **not**
  contain `ps`. The fixture is created under `apps/`, and `make -C` prints
  `Entering directory .../apps/zz-test-common-wrapper` — and `apps` contains
  `ps`. Section 1's Entering-directory bug, this time hidden inside a path
  component rather than at the start of a line. `--no-print-directory` fixes it.
- `docs-site` checked the **filesystem** for `.next`, `node_modules` and stray
  images. All are gitignored, so it failed on any machine that had built the
  site and passed on a clean CI checkout — host-dependence pointing at the
  developer rather than at CI, the mirror image of the usual case. The claim is
  about what the import committed, so it now asks `git ls-files`. Its `find` for
  images was walking `node_modules` and reporting assets shipped by vendored
  packages.

### Two tests that were executing real work

`docs-site` also ran `rm -rf node_modules` followed by `make -C sites/docs
build` — a real `bun install` over the network and a Next.js build, which
destroyed the developer's installed dependencies on the way past.
`apim-simulator-makefile` ran `make app-js-check`, which executes `biome`: a
tool this repo pins nowhere, does not install in CI, and which is absent from
this host.

Both are now static assertions over the Makefiles, following the precedent set
by the `make -n` guard test in section 12: where running the thing is either
destructive or impossible, assert the wiring instead. Both still fail if the
contract they describe changes.

### A duplicate dict key, and no Python linting at all

`tests/app_contracts.py` had `"lima"` twice in one dict literal, so Python kept
the second value and the Keycloak image contract asserted a registry host —
`192.168.64.1:5002` — that appears **nowhere else in the repository**. The
correct `host.lima.internal:5002` entry was shadowed and dead. A second dict had
the same key twice with the same value, meaning that contract has only ever
validated lima where the sibling function below it validates both targets.

`ruff` reports both as F601, and `ruff` is installed. Nothing in `make lint`
runs it: the repo lints YAML, Markdown, shell, HCL, Cilium and Kyverno, but not
its own 5,800-line Python contract library. Worth closing, and deliberately not
closed here — a first `ruff` run also reports unused imports, so it is its own
change rather than a rider on a green-up.

Extending the second contract to `kind` is also left undone on purpose:
`kind.tfvars` has no `external_workload_image_refs` map, so the validator fails
on it. That is a real coverage gap needing an owner, not a test edit.

### And one caused by the section 12 fix

`platform-workflow` ran `make -n readiness` as a proxy for "the target is
wired". The dry-run refusal added in #198/#199 now rejects that — correctly,
because `readiness` recurses into `prereqs`, and `-n` there would run the real
operation. So a fix landed in the gate broke a test outside it, and nothing
reported the breakage for a day. It now reads the goal out of the make database
instead of asking make to pretend.

### What is left

Nine files. Six are the untriaged docker set, and after `reset-local-state`
turned out to be deleting the operator's uv cache, they should be run
deliberately and watched rather than swept in. The other three are
`vanilla-js-typecheck` (15/61), `grafana-dashboard-quality`, which queries a
live Prometheus and cannot be hermetic as written, and `platform-workflow-ui`,
which hangs rather than fails.

### 9 to 8: vanilla-js-typecheck, and what #125 left behind

15 of 61 failing, and almost all of it traces to one architectural change that
the contracts never followed.

**#125 deleted every app's `style.css`.** The five canonical browser apps now
load the pinned 5h3ll-ui CDN stylesheet followed by the shared
`/app-shell.css`, and own no CSS of their own. Six contract helpers still read
`apps/<app>/app/internal/app/web/style.css` and died with `FileNotFoundError`
before asserting anything. They now skip a stylesheet that is not there, which
is the guard `browser_sso_static_allowlist_contract_violations` already used a
few hundred lines further down the same file. The checks are about an app not
re-owning shared styling, which is vacuously true when it owns no stylesheet.

**The palette moved behind the library's tokens.** `--page: #f6f8fb;` became
`--page: var(--background, #f6f8fb);` and so on for every token, so the shared
sheet defers to 5h3ll-ui and falls back to exactly the previous hexes. `--border`
was renamed `--app-shell-border` because `--border` now belongs to the library.
The contract asserted the old literals; it now asserts the layered form, with
the same hex values it always did.

**Selectors grew `:not()` guards for the same reason.**
`:where(input, textarea, select)` became
`:where(input:not(.input), textarea:not(.textarea), select:not(.select))` so
shared rules stop overriding the library's own classes, and the formatter
wrapped the longer ones across lines. Both contracts locating a block by exact
selector string reported the block as *missing* while every declaration inside
it was correct. They now normalize selectors before matching and assert on the
declarations, which is where the meaning lives.

### Assertions that were testing the formatter

`renderStatusInto(apiStatusEl` matched nothing, not because the call was gone
but because Biome wraps a three-argument call across lines. The code did exactly
what was being asserted. Collapsing whitespace after `(` before matching fixes
the class, not just the instance -- any single-line call fragment in this module
was one formatter run away from the same failure.

Two more were an abstraction level out of date rather than wrong:
`subnetcalc` now composes `keyValueArticleElement`, which calls
`keyValueTableElement` internally -- *more* use of the shared helpers, which is
the thing the contract exists to encourage -- and sentiment's comment article
carries `"comment card"` since the 5h3ll-ui adoption, where the contract wanted
the class list to be exactly `"comment"`.

### The contract that forbade what TypeScript requires

`browser_public_unknown_contract_violations` bans `unknown` from public browser
surfaces. It flagged `auth-chat`:

```javascript
const config = /** @type {RuntimeConfig} */ (
  /** @type {unknown} */ (readRuntimeConfig("AUTH_CHAT_CONFIG"))
);
```

That cast is not a lapse, it is what the compiler demands. Removing it and
running `deno check` gives:

```text
TS2352: Conversion of type 'JSONObject' to type 'RuntimeConfig' may be a
mistake because neither type sufficiently overlaps with the other. If this was
intentional, convert the expression to 'unknown' first.
```

So the contract as written offered a choice between satisfying it and compiling.
The `/** @type {unknown} */` cast idiom is now exempt; `unknown` in a declared
public shape, which is the actual target, still fails.

The second hit was real. `apps/idp-sdk/src/index.ts` exported
`type IdpStatus = Record<string, unknown>` while every sibling type in that SDK
is concrete. `schemas/idp/status.schema.json` and `schemas/idp/action.schema.json`
already describe the shape, so `IdpStatus` and a new `IdpAction` now state it.
Nothing outside the SDK consumed the type, and `deno check` passes.

### biome is not installed anywhere

Two tests invoked `biome`, which this repo pins nowhere, does not install in CI,
and which is absent from this host -- the third and fourth instance in this
effort after `apim-simulator-makefile`. Their hermetic contract assertions run
unconditionally; only the tool invocation is now guarded by
`command -v biome || skip`, the idiom `tests/app-healthcheck-commands.bats`
already uses for `python3`.

That biome is unpinned while `deno` is present is worth deciding on its own.
Every browser app's `js-check` depends on it, so `make -C apps js-check` cannot
currently run on a clean machine or in CI.

## 16. Two Linters The Repo Did Not Run

Both gaps were found by the section 15 work rather than by anything watching for
them, and both had already cost something.

### Python was never linted

`tests/app_contracts.py` is ~6,000 lines that every bats suite imports, and
`make lint` covered YAML, Markdown, shell, HCL, Cilium and Kyverno -- not it.

The cost was concrete. A dict literal carried `"lima"` twice, so Python kept the
second value and the Keycloak image contract asserted a registry host,
`192.168.64.1:5002`, that appears nowhere in the repository, while the correct
`host.lima.internal:5002` entry sat shadowed and dead. `ruff` reports exactly
that as `F601`, and `ruff` was already pinned in the n-dotfiles global mise
config. It was installed and never invoked.

`make lint-python` now runs it through `scripts/lint-python.sh`, following the
same shape as the other lint scripts: a `--dry-run`/`--execute` interface, a
missing-binary path with install hints, and tracked-file discovery via
`git ls-files`.

**The rule set is pinned in `ruff.toml` rather than left to ruff's defaults.**
n-dotfiles tracks ruff at `latest`, so the default selection would change under
the repo between releases -- the same drift this effort exists to end. The
selection is `E4,E7,E9,F,I,UP,B,SIM`: 5 findings on the current tree, all
meaningful. `FURB` and `RUF` were considered and rejected; they add 15 findings,
every one cosmetic (`re.S` versus `re.DOTALL`), and none describes a defect.

The five were an unused `sys` import, an unsorted import block, a quoted type
annotation, and **two dead `content = makefile.read_text(...)` reads** left
behind when those checks moved from parsing Makefile text to
`_evaluated_make_targets`. CI installs `ruff==0.16.2` alongside the pinned
yamllint.

`tests/lint-python.bats` guards the wiring, and one case asserts `F` is in the
selection rather than asserting the tree is currently clean, so the rule that
would have caught the duplicate key cannot be dropped silently.

### biome was installed nowhere at all

Four tests across three files invoke `biome`: `apim-simulator-makefile`,
and two in `vanilla-js-typecheck`. It was pinned in no mise config, installed by
no CI step, and absent from this host, so `make -C apps js-check` could not run
on a clean machine or on a runner. `deno`, its companion in the same target, was
present only as an Arch package -- the same host-dependence in a quieter form.

Both are now pinned in the n-dotfiles global mise config, and CI installs
`@biomejs/biome@2.5.8` and `deno 2.9.5` explicitly.

**Installing it proved the point immediately.** `make -C apps js-check` was
failing, with seven findings in `apps/shared/appshell/app-shell.js`: six
`forEach` callbacks returning a value (`useIterableCallbackReturn`) and one
missed optional chain. The same function already used braced callback bodies for
several of its calls, so the six were an internal inconsistency rather than a
style choice. Fixed, plus an 82-line reformat of a 1,288-line file to match the
formatter -- contained, because the file was already close.

That is the fourth tool in this effort found to be missing rather than
misconfigured, after `uv`, `helm` and the host locale. The pattern is worth
stating plainly: **a check that cannot run reports nothing, and reporting
nothing is indistinguishable from passing** unless something asserts the tool
is present. The CI install step now ends with `biome --version` and
`deno --version` for exactly that reason, so a broken install fails the job
rather than quietly turning the browser contracts into skips.

### biome dumped core three times

Worth recording because it is unresolved. `biome` 2.5.8 from mise left three
50MB core files -- two in `apps/shared/appshell/`, one in n-dotfiles from a bare
`biome --version`. It has not reproduced since: `--version` and `check` now run
cleanly, and the error path exits 1 without crashing. Treat a `core.*` file
appearing next to a JavaScript check as this, not as a repo bug.

`core.*` is deliberately **not** added to `.gitignore`. The full test-ci run that
followed failed with:

```text
FAIL the command under test changed the working tree
     removed:    ?? apps/shared/appshell/core.888778
```

`check-worktree-unchanged.sh` caught them, which is the behaviour worth keeping.
Ignoring the pattern would make a future crash silent, and the whole point of
this document is that silence is the expensive failure mode.

### Two flaky timing tests already inside the gate

Found by running the gate on a machine that was also compiling something else.
`tests/parallel.bats` and `tests/check-provider-version.bats` both prove bounded
concurrency by wall clock: three items at concurrency two, one second each, so
unbounded finishes near 1s, bounded near 2s and serial near 3s. Those landmarks
are one second apart, which means a busy host fails the test for being busy
rather than for being wrong. This is section 2's "timeouts assume fast hardware"
living inside the safety net itself.

Both now sleep two seconds per item, moving the landmarks to 2s, 4s and 6s, and
assert `4 <= elapsed < 6`. Two seconds of headroom on each side instead of half
a second. Verified by running the same helper at concurrency 3 (2s, correctly
below the band) and concurrency 1 (6s, correctly at the top of it).

The assertion was also wrong in a quieter way. It read:

```bash
[[ "${output}" =~ elapsed=1|elapsed=2 ]]
```

That regex is unanchored, so `elapsed=10` and `elapsed=20` matched it too --
a serial run slow enough would have passed. Both now compare integers.

### A test that hangs depending on what stdin is

`make test-ci` stopped dead for twelve minutes on
`tests/audit-shell-scripts.bats`, test 11. The blocked process was:

```text
rg -l shell_cli_handle_standard_flag -g *.sh
```

There is no path argument. `rg` then decides what to search from stdin: a TTY
or `/dev/null` makes it walk the current directory, but an **open pipe makes it
read stdin**, and it waits there forever. bats gives each test a pipe, so the
suite could hang on this line at any time.

The first guess -- that it silently searched nothing and passed vacuously --
was wrong, and worth recording because it is the more attractive story. Checked
rather than assumed:

```text
$ rg -l 'shell_cli_handle_standard_flag' -g '*.sh' < /dev/null | wc -l
76
```

So CI is unaffected: a workflow step's stdin is `/dev/null`, which makes `rg`
behave correctly. That is precisely what keeps this invisible. The failure only
appears when someone pipes into `make test-ci`, and then it presents as a hang
rather than a failure -- no output, no timeout, nothing to attribute it to.

The fix is one character: pass `.` so `rg` never consults stdin. Verified by
running the fixed form with a deliberately blocking pipe on stdin, where it now
returns all 76 matches immediately.

`tests/platform-workflow-ui.bats`, still in the backlog, also hangs rather than
fails. Worth checking it for this same shape before assuming it is a different
bug.

## 17. Handoff

State as at 2026-08-15, end of the CI gate burn-down.

### Where the gate stands

`make test-ci` is **620 passing, 0 failing**, up from 396 when this started.
`make lint` is clean and now includes `lint-python`. The section 15 backlog is
**37 -> 8**.

### The eight files still outside the gate

Six are untriaged because they drive `docker build`/`run`/compose:
`backstage-compose`, `backstage-portal`, `devcontainer-makefile`,
`smoke-sentiment-api-image`, `validate-app-runtime-surfaces`,
`validate-docker-optimization-contracts`.

**Run these one at a time and watch them.** `reset-local-state.bats` turned out
to be deleting the operator's real `~/.cache/uv`, and that was a file with no
docker in it at all. The risk here is higher, not lower.

The other two need more than an assertion fix:

- **`grafana-dashboard-quality`** (2/4) asserts that live Prometheus queries
  return series. It cannot be hermetic in its present shape. It needs either a
  recorded fixture or a decision that it is a cluster test rather than a gate
  test. That is a judgement about what the gate is for, not a bug.
- **`platform-workflow-ui`** (2/11) *hangs* rather than fails; `bats` produces
  all 11 results and then never exits, so a 120s timeout kills it at `rc=124`.
  It starts an HTTP server per test and something is not being reaped at
  teardown. Checked against the `rg`/stdin hang in section 16 -- **not** the same
  cause. A hanging test in a gate is worse than a red one, so fix the teardown
  before listing it.

### Open decisions, not open bugs

- **`image_catalog_target_ref_contract` only validates lima.** Extending it to
  kind fails because `kubernetes/kind/targets/kind.tfvars` has no
  `external_workload_image_refs` map. Real coverage gap; closing it means
  changing target tfvars, which needs an owner.
- **`biome` has no config and no repo-level pin.** It runs on defaults, so its
  rule set moves with the version. CI pins `2.5.8` and n-dotfiles tracks
  `latest`, which will diverge. A `biome.json` would settle it.
- **`ruff.toml` excludes `FURB` and `RUF`** as 15 purely cosmetic findings.
  Revisit if you want them.

### Gotchas worth not rediscovering

- **`rg` with no path argument reads stdin when stdin is a pipe.** It hung the
  suite for twelve minutes. Always pass a path. CI hides this because a workflow
  step's stdin is `/dev/null`.
- **Setting `HOME` does not sandbox a test.** It sandboxes only the tools that
  read `HOME`, and which those are is not knowable from the test. `uv cache dir`
  ignores it.
- **A fixture git repo inherits global config**, including `commit.gpgsign`.
  Pin it off, as `git-hooks.bats` already did.
- **Wall-clock concurrency assertions need landmarks further apart than the
  noise.** One second is not enough on a machine doing anything else.
- **`biome` 2.5.8 left three 50MB `core.*` files** and has not reproduced since.
  `core.*` is deliberately not gitignored so `check-worktree-unchanged.sh` keeps
  catching it.

### The pattern this whole effort found

Stated once, because it recurred in every section: **a check that cannot run
reports nothing, and reporting nothing is indistinguishable from passing.**

It appeared as a test outside the gate, a tool installed nowhere, an allowlist
nobody could see rotting, an assertion that could never match, a scanner blind
to dotfiles, and a workflow that was never triggered. In every case the fix was
cheap and the finding was only expensive because nothing said it was there.

### Correction 2026-08-15: the first CI run on the new gate went red

PR #200's first run failed, and the finding is the best possible advertisement
for the exercise: `make lint` passed -- ruff, biome and deno all installed
cleanly -- and two tests in `tests/reset-local-state.bats` failed on
`ubuntu-latest` having passed on this host.

```text
# (in test file tests/reset-local-state.bats, line 68)
#   `[[ "${output}" == *"${TEST_HOME}/Library/Caches/pip"* ]]' failed
```

`reset-local-state.sh` resolved each host cache by asking the tool **or**, only
if the tool said nothing, checking the well-known locations. Those were
alternatives rather than additions. `pip cache dir` returns `~/.cache/pip`, so
on a host with pip the macOS-style `~/Library/Caches/pip` was never looked at at
all. **Arch ships no pip and ubuntu-latest does**, so the test passed here and
failed there.

The tool lookup and the known locations are now additive; `append_unique_path`
already deduped the overlap. Verified by stubbing a `pip` onto `PATH` to
reproduce the runner's condition exactly -- the same two assertions failed at
the same two lines -- and confirming the fix passes both with and without pip.

The suite no longer depends on the answer. A new case stubs `pip`, creates both
cache locations, and asserts **both** are collected, so the behaviour is pinned
rather than inherited from whatever the host has installed. It fails on the
pre-fix script.

This is section 1's thesis reaching its own conclusion: the file had been in the
backlog, was triaged as green on this workstation, joined the gate on that
basis, and the very first run on different hardware found a real defect in the
script it was testing. That is the gate working -- and it is also a reminder
that "passes locally" was never evidence of anything.

## 18. Verifying On Ubuntu Locally, And What Slicer Leaves Behind

The pip bug in section 17 cost a push, a CI round trip, and a red build to find
something a local Ubuntu box would have shown in minutes. This host has Slicer
(Firecracker microVMs), so that loop is avoidable. The workflow is recorded in
the n-dotfiles project memory `slicer-verification-workflow`, which is why it
did not surface here -- **memories are per-project, and this is a different
project**. Worth knowing before re-deriving it a third time.

### The shape of it

```bash
sudo -E slicer up ~/sandbox.yaml          # operator runs this; the daemon needs root
slicer workspace --rm --hostgroup sandbox --tag purpose=platform-gate
slicer wt push sandbox-1 <dir>            # carries uncommitted working-tree changes
slicer vm exec sandbox-1 -- bash -lc '...'
```

Client commands need no sudo -- `nick` is in the `slicer` group and can read
`/var/lib/slicer/auth/token`. Only the daemon needs root.

The base image is **Ubuntu 22.04.5 with `/bin/sh -> dash`**, which is precisely
the condition behind the section 13 `pipefail` failure. That class is now
reproducible without pushing.

It is *not* automatically a stand-in for `ubuntu-latest`. The image ships **no
pip at all**, so it would not have reproduced the section 17 failure by default;
`python3-pip` has to be installed deliberately to match the runner. A VM that
differs from CI in a *different* direction just relocates the blind spot.

### Do not run slicer from inside the repository

This is the part worth remembering. The daemon runs as root and writes into the
directory the command was invoked from. Running `slicer workspace` with the repo
as the working directory left three root-owned artifacts in the repo root:

| Artifact | Mode | What it is |
| --- | --- | --- |
| `.slicer/` | `drwx------ root` | daemon state |
| `sandbox-1.img` | `-rw------- root` | the live VM disk, 25GiB apparent, ~900MB sparse |
| `vm_agent_secret` | `-rw------- root` | the VM agent's auth token |

Each one broke something different, and the failures were not obviously related
to each other:

- `.slicer/` made `slicer wt push` fail with `permission denied`, because the
  overlay walks the **filesystem** rather than git -- so adding it to
  `.gitignore` did not help. The push only worked after staging a clean copy of
  the tree outside the repo.
- `sandbox-1.img` broke `git add -A` outright: `unable to index file`. Not a
  warning, a hard failure. `git status` could not walk `.slicer/` either.
- `vm_agent_secret` is a **credential**. Mode 600 and root-owned is the only
  reason `git add -A` did not stage it. That is luck, not design.

All three are now in `.gitignore`, which keeps the working tree usable if it
happens again. **The actual fix is to invoke slicer from outside the repo.**

The disk image must not be deleted while the VM is running -- it *is* the VM.
Clean up in order: `slicer vm delete sandbox-1`, then remove the artifacts as
root.

### What the VM found once it was made faithful

The first full run in the microVM reported 13 failures against CI's 2. Rather
than assume they were noise, each was checked against the CI log for the same
run: **all 13 were `ok` on the runner**. That comparison is the whole method —
a difference between the VM and CI is a question, not a verdict.

Closing them took four environment additions and turned up three real defects:

| Cause | Tests | Verdict |
| --- | --- | --- |
| No Go | 8 | VM gap; runners preinstall it |
| ripgrep 13.0.0 without PCRE2 | 1 | VM gap; 22.04 ships an older build than 24.04 |
| No helm | 1 | VM gap; runners preinstall it |
| `cp -R` fallback with no exclusions | 1 | **real bug** |
| `ubuntu` contains `bun` | 1 | **real bug** |
| mawk instead of gawk | 2 | **real latent bug** |

Final state: **621/621, exit 0**, on both Arch and Ubuntu.

#### The fallback that copied everything

`copy_app_repo_source_dir` in `sync-gitea-app-repo.sh` excluded `.git`,
`node_modules`, `.venv`, `__pycache__`, `.run`, `.pytest_cache` and
`.ruff_cache` -- but only in its `rsync` branch. The `else` branch was a bare
`cp -R` with **no exclusion mechanism at all**, so on a host without rsync the
projected Gitea app repo receives build output and dependency trees wholesale.

Arch, macOS and `ubuntu-latest` all ship rsync, so that branch had never once
executed. `tests/validate-gitea-app-repo-sync.bats` asserts exactly this and
would have caught it immediately -- given a host that takes the branch.

Both paths now share a single `APP_REPO_SOURCE_EXCLUDES` list, with the fallback
using `tar --exclude`. Verified twice: standalone with the exclusions applied to
a fixture tree, and in the rsync-less VM where the test now passes.

#### `ubuntu` contains `bun`

`tests/subnetcalc-makefile.bats` asserted `[[ "${output}" != *"bun"* ]]` on the
output of `make -C`, which prints `Entering directory '<abspath>'`. The absolute
path is the operator's, so the test was quietly asserting something about their
home directory -- and `/home/ubuntu` contains `bun`.

Fourth instance of section 1's Entering-directory bug, after the `$HOME` case,
the JSON-parse case, and `apps` containing `ps`. The pattern is now unmistakable:
**a substring assertion over `make -C` output is an assertion about the
filesystem path it happens to run from.** `--no-print-directory` is the fix
every time.

#### The render that needs gawk and does not say so

`render_prometheus_application_manifest` uses `awk`. Under **mawk** it emits
`alertmanager: enabled: false` when `ENABLE_ALERTMANAGER=true` was requested --
wrong output, exit status 0, no warning of any kind.

Stock Ubuntu ships mawk. Arch ships gawk, and the GitHub runner images install
gawk, so both environments this platform is normally exercised in hide it.

**Not fixed here, deliberately.** gawk was installed in the VM to match CI
rather than rewriting the awk program, because the choice is a real one: either
make the script mawk-safe, or declare gawk a prerequisite and check for it the
way `require` already does for `curl`, `jq` and `perl`. This repo already runs a
macOS CI job specifically because awk implementations differ, so it has the
appetite for the former -- but it should be decided, not slipped in beside a
green-up.

A silently wrong render is worse than a failed one. Whichever way it goes, it
wants a guard rather than a comment.

## 19. Back On macOS: What The Sweep Missed

The portability pass was written and verified on Arch. This is the first time
the repo's own gates ran on the Mac since, which is the only way to find what a
Linux-only check cannot see.

| Fact | Value |
| --- | --- |
| Host | Darwin 25.6, arm64 |
| `make` | GNU Make **3.81** (Apple stock, not 4.x) |
| `/bin/bash` | **3.2.57** |
| `awk` | BWK awk 20200816, not gawk |
| `sort` | Apple sort 2.3 |

Result: across the 131 files and ~6,200 insertions of #195 through #200,
**one** genuine macOS regression, and it was in a test fixture rather than
production code. The `uname -s` branching, the Darwin paths in
`reset-local-state.sh`, the memory preflight, the dhi credential helper default,
and the no-op systemd timer all behave correctly here.

Four things that were verified rather than assumed, because each could
plausibly have broken and none did:

- The parse-time `make -n` refusal works on Make 3.81 for `-n`, `--just-print`,
  `--dry-run` and `-rn`, and does **not** false-positive despite
  `--no-print-directory` containing an `n`. Make emits a leading space in
  `MAKEFLAGS` when no short flags are set, so `$(firstword -$(MAKEFLAGS))` is
  `-` rather than `---no-print-directory`.
- `SHELL := /bin/bash` resolves to 3.2 here. No tracked makefile uses a Bash 4
  construct, so pinning it broke nothing -- see section 19.4 for why that was
  luck rather than coverage.
- The Yarn Berry `awk` parser added in #196 runs under BWK awk. The handoff
  records it as checked under `awk --posix` and `awk --traditional`, which are
  **gawk** flags; that is a different interpreter, not stock macOS awk. The
  conclusion held, the evidence did not.
- `sort -V` and `sort -z` both work on Apple sort, which the version resolver
  and `lint-python.sh` depend on.

### 19.1 The one regression: a GNU-only `date` in a fixture

`tests/update-versions.bats` built its fake-`curl` timestamps with
`date -u -d "@<epoch>"`. BSD `date` has no `-d`; the fixture runs
`set -euo pipefail`, so the fake curl died and took the test
`tools resolver picks the newest cooldown-eligible release` with it.

What makes this precise rather than a general miss: **every other date call in
the repo already had the portable form.** `epoch_from_iso` and `date_from_epoch`
in `scripts/update-versions.sh`, the three call sites in
`check-component-version.sh`, and the three in
`kubernetes/kind/tests/check-version.bats` all try BSD first and fall back to
GNU. Two lines in one fixture were the only sites that missed the pattern -- and
they guard the cooldown resolver that #195 exists to repair.

Fixed with the same `epoch_to_iso` shape as `date_from_epoch`.

### 19.2 Why CI could not have caught it

`tests/update-versions.bats` is in `CI_BATS_TESTS`, which runs only on
`ubuntu-latest`. The `host-portable-bats-macos` job runs
`HOST_PORTABLE_BATS_TESTS`, which was seven files -- all of them added in the
same session that created the job.

So the macOS job covered the new work and nothing else, while ~90 hermetic
files that would run fine on macOS stayed Linux-only. Running the full
`make test-ci` here proved that: 620 of 621 passed. The job was not a macOS
gate, it was a regression test for one session's output.

`tests/update-versions.bats` is now in the host-portable set. The broader
question -- whether the macOS job should simply run `make test-ci` -- is left
open deliberately, since some of that set reads host state.

### 19.3 Two guards that were already red

Both were invisible for the same reason, and it is the reason section 15 exists.

**`kubernetes/kind/tests/makefile.bats` asserted a guard that no longer
existed.** #198 wrote the refusal as a literal `filter plan apply,$(MAKECMDGOALS)`
and asserted that string. #199 widened the guard to six goals behind
`$(KIND_DRY_RUN_UNSAFE_GOALS)` and left the assertion untouched. It has been red
on `main` since, and the file is outside `CI_BATS_TESTS`. The assertion now
checks that the guard is wired to the list and refuses at make level, and leaves
*which* goals to the list test beside it.

**`lefthook` was pinned but hinted as `latest`.** `LEFTHOOK_VERSION` has been in
`toolchain-versions.sh` all along, but `pinned_version_for_tool` never mapped
it, so `install-tool-hints.sh` emitted `mise use lefthook@latest`. That is the
exact cooldown bypass the pinned-hint work in #195 set out to close, surviving
inside the change that closed it.

### 19.4 `make -n` was guarded for kind only

`kubernetes/lima/Makefile` had the identical shape and no guard. Its `reset` is
one backslash-continued recipe block holding `$(MAKE) stop-host-gateway-proxy`,
`limactl delete --yes --force`, and three `rm -rf` calls. Confirmed on Make 3.81
that such a block executes in full under `-n`, so `make -C kubernetes/lima -n
reset` would have deleted the operator's Lima VMs and Terraform state.

The guard is now mirrored, covering `apply plan prereqs reset stop-lima`.

**The membership was derived, not copied, and that mattered.** A first pass
added `sync-image-cache` "for parity with kind" and immediately broke
`tests/kubernetes-sync-image-cache-adapter.bats`, which runs
`make -n sync-image-cache` and reads the output. Kind's recipe opens with a
`$(MAKE)` line; lima's has no `$(MAKE)` at all, so nothing is exempt and `-n` is
a genuine preview there. `start` is absent for the same reason: it is a bare
`@$(MAKE) lima-vms-up` line, so the child make inherits `-n` and previews
correctly.

The criterion is a *logical* recipe line holding both `$(MAKE)` and a mutating
command. Section 12 already recorded that auto-deriving that set silently
passes; this adds the converse -- copying another target's set silently
over-refuses, and over-refusal breaks working callers rather than failing
loudly. The lima list test now asserts both directions.

### 19.5 The Bash 3.2 check could not see makefiles

`check-bash32-compat.sh` scanned tracked `*.sh` only. Since #197 and #199 pinned
`SHELL := /bin/bash` in `mk/common.mk` and `mk/go-app-core.mk`, every recipe in
the files that include them is Bash under test -- 5.x on Arch, 3.2 on macOS. A
Bash 4 construct in a recipe would have passed every Linux check and broken
here, which is precisely the class this check exists to catch.

The scan now covers tracked `Makefile` and `*.mk` as well: 207 scripts plus 46
makefiles, 253 files, clean. Nothing violated it today, so this closes a blind
spot rather than fixing a live defect.

### 19.6 The onboarding path did not know the tools the gate requires

`install-tool-hints.sh` is what `kubernetes/kind/docs/prerequisites.md` tells a
fresh host to run, and #195 rewrote it for exactly that role. It had no hint for
`ruff`, `deno`, `biome`, `uv`, `rg`, `lefthook`, `markdownlint-cli2` or
`cosign`.

Most of those became **required** in the same range. `make lint-python` needs
ruff; the apps `js-check` needs biome and deno; the root Makefile shells out to
`rg`; #200 installed all three in CI, pinned. So `lint-python.sh` would fail
with `ruff not found` and then print a hint telling the operator to go read the
vendor's documentation.

Names were verified against the tools themselves rather than recalled:

| Source | Checked with |
| --- | --- |
| mise | `mise registry` |
| Homebrew | `brew info --formula` |
| arkade | `arkade get -o list` |

That is how the `rg` case surfaced: arkade's catalogue entry is `rg`, while
every other manager calls the package `ripgrep`. `normalize_tool` maps the
binary name the Makefile invokes, and `arkade_tool_name` maps back.

pacman entries were added only for the five packages in the official repos.
`biome`, `lefthook` and `markdownlint-cli2` fall through to the next manager
rather than assert an AUR package that may not exist -- the Arch names in #195
were verified against the official repos, and guessing here would quietly break
that.

### 19.7 `@SCRIPT_NAME@` in forty-nine scripts

The repo's usage idiom is `cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"`. The
`1s` substitutes on line one only. That is invisible until a script puts a
placeholder below line one, which #195 did when it added the
`INSTALL_TOOL_HINTS_MANAGERS` example -- so `--help` printed the raw
`@SCRIPT_NAME@` to the operator.

All 49 scripts now use the global `s|...|g` form. Guarded twice: rendered help
must contain no placeholder, and a static repo-wide assertion that no tracked
script uses the line-one-only form, because the defect cannot be seen until
someone adds the second placeholder.

### 19.8 Host state, not code

Carried here so the next macOS session does not rediscover them:

- `.env` predated `OAUTH2_PROXY_COOKIE_SECRET`. `make init-env` appends it and
  preserves existing values; this is what that target is for.
- `KIND_ENABLE_BACKSTAGE` defaults to `off` since #195. A bare `900 apply` on
  the Mac no longer includes Backstage unless it is passed explicitly.
- `PLATFORM_TIMEOUT_SCALE` is the knob for slower hosts, and the Mac is the
  slower host in this pair.

### 19.9 Verification

| Gate | Before | After |
| --- | --- | --- |
| `make lint` | clean | clean |
| `make test-ci` | 620/621, exit 2 | **628/628, exit 0** |
| `make test-host-portable` | 7 files | **56 tests, 8 files, exit 0** |

Every fix above carries a guard, and each guard was verified by reproducing the
condition it catches: shrinking the lima goal list, adding a `mapfile` recipe to
a makefile fixture, reintroducing the line-one `sed` form, and narrowing the
bash32 scan back to `*.sh`.

### 19.10 Picking this up on Arch

Written for the next session on the Omarchy box, which may have its own work to
fold back in. Nothing here was pushed, and nothing touched cluster state -- the
Arch stage 900 cluster is untouched by all of it.

**The likely conflict surface is section 19.7.** The `@SCRIPT_NAME@` fix rewrote
one `sed` line in **49 scripts** across `scripts/`, `kubernetes/scripts/`,
`kubernetes/*/scripts/` and `terraform/kubernetes/scripts/`. It is mechanical
and behaviour-preserving, but it touches the usage block of nearly every script
in the repo, so any Arch-side edit to a `usage()` will collide. If that happens,
take the Arch content and re-apply the one-character change: the invariant is
`sed "s|@SCRIPT_NAME@|${0##*/}|g"`, and
`tests/install-tool-hints.bats` asserts repo-wide that no `1s|` form survives.
Resolving in that direction is always correct.

**Re-verify on Arch, because macOS could not:**

| Item | Why it needs Arch |
| --- | --- |
| pacman hints in 19.6 | pacman is not on PATH here, so those map entries were reasoned about, not executed. Run `INSTALL_TOOL_HINTS_MANAGERS="pacman" scripts/install-tool-hints.sh --execute --plain cosign deno ripgrep ruff uv` and confirm each package resolves. |
| The lima guard on Make 4.x | Verified on Make 3.81 only. The `MAKEFLAGS` leading-space behaviour that makes `$(firstword -$(MAKEFLAGS))` work is the load-bearing detail; kind's guard has run on 4.x since #198, so this is confirmation rather than doubt. |
| bash32 scanning makefiles | The scan now runs GNU grep over 46 makefiles instead of BSD grep. The ERE patterns are POSIX, but the file set is new, so a false positive would appear on Arch first. |
| Manager ordering | With both mise and pacman present, the chain resolves differently than it does here. Worth one `make -C kubernetes/kind prereqs` to see the hints an Arch operator actually gets. |

**Behaviour change to expect in muscle memory.** `make -C kubernetes/lima -n`
now refuses for `apply plan prereqs reset stop-lima`. If a session reaches for
`-n` on lima to preview a stage, the answer is `make <stage> plan`, same as
kind. `make -n sync-image-cache` and `make -n start` still work, deliberately;
see 19.4.

**Open, and left open on purpose:**

- Whether `host-portable-bats-macos` should run `make test-ci` outright rather
  than a curated list. 19.2 argues the curated list is the wrong shape, but
  some of that set reads host state, so it is a decision rather than a patch.
- Section 18's mawk finding is untouched. It is still the case that
  `render_prometheus_application_manifest` produces silently wrong output under
  mawk, and that wants deciding on the Linux side where mawk actually appears.
- The `.claude/settings.local.json` permission entries added in #195 and #196
  are still tracked in git. Not addressed here, but a local settings file
  accumulating in the repo is worth a decision.

**If the Arch side has already fixed any of this independently**, prefer the
Arch version of the *fix* and keep the guard from here. Every item in section 19
carries a test that fails when the condition returns, and those are what stop
the same finding arriving a third time -- the guards are the durable half, not
the one-line changes they protect.
