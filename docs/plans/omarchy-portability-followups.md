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

Two changes still outstanding, both small:

- add a `pull_request` trigger to `ci.yml`
- install `uv` in `version-audit.yml` (`astral-sh/setup-uv`, or mise)

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

## 5. Two Sources Of Truth For Tool Pins

`install-tool-hints.sh` derives pins from `.devcontainer/toolchain-versions.sh`,
so hints track bumps automatically — confirmed when terragrunt moved to `1.1.2`.
The committed `mise.toml` is hand-written and will silently go stale the moment
`update-versions.sh --apply` moves a pin.

Either generate `mise.toml` from `toolchain-versions.sh` behind a make target, or
add a drift assertion to `.devcontainer/check-toolchain-surface.sh`, which
already guards that surface.

## 6. Charts Can Never Be Bumped

`update-versions.sh --only charts` returns `deployed_unavailable` for all twelve
components, so nothing is ever eligible and `--apply` skips everything. Updates
are genuinely available:

| Chart | Pinned | Available |
| --- | --- | --- |
| argo-cd | 10.2.1 | 10.3.0 |
| prometheus | 29.20.0 | 29.21.0 |
| otel-collector | 0.165.0 | 0.166.0 |

Determine what `check-component-version.sh` needs to read deployed state, and
whether the audit should degrade to a version-only comparison when no cluster is
present rather than blocking all chart bumps.

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

## 9. Repo Hygiene And Onboarding

- An empty tracked file named `cp` sits at the repo root, committed in #164 —
  a mistyped `cp .env.example .env`.
- `.playwright-mcp/` holds twenty-odd tracked console and page logs from
  2026-04-27. Should be gitignored.
- `.skill-loop-progress.md` is a 105KB tracked working file.
- There is no `make init-env`. The README implies `.env` is just a copy of
  `.env.example`, but `OAUTH2_PROXY_COOKIE_SECRET` must be hand-generated and
  stage 100 hard-fails without it. A target that writes `.env` with a generated
  cookie secret would remove a silent onboarding trap.

## 10. Credential Hygiene On Linux

`docker login` on Linux with no credential helper stores base64 credentials in
plaintext in `~/.docker/config.json`. `dhi-creds-offline.sh` already anticipates
a file-backed helper; the Linux equivalent is
`docker-credential-secretservice` or `docker-credential-pass`, and the
prerequisites documentation should say so.

Worth recording, because it cost real time: **`dhi.io` authenticates with an
ordinary Docker Hub account.** There is no separate registration and no paid
tier for the core images. A `docker login dhi.io` failure is almost always
either a missing `dhi.io` entry in `config.json` or a password being used where
the account requires a personal access token.
