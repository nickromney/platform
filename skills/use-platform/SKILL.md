---
name: use-platform
description: Orientation and workflow guide for the `platform` repository. Use when an agent is asked to work in a checkout of this repo, when the user mentions the platform repo or its local Kubernetes stacks, or when the agent needs to choose the correct Makefile, docs path, env-sensitive entrypoint, or verification command before making changes.
---

# Use Platform

Confirm the workspace root is the repository checkout that contains `Makefile`, `mk/`, `apps/`, `kubernetes/`, and `sd-wan/`.

Start with the repo-local guidance and entrypoints, not the top-level README:

- Open `AGENTS.md` at the repo root.
- Run `make` or `make help` at the repo root.
- Treat root `make`, `make prereqs`, and `make test` as routing/help entrypoints. The mutating or repo-wide checks at the root are `make lint` and `make fmt`.

Choose the focused Makefile before reading deeper docs:

- App or frontend work: `make -C apps help` or the nearest app Makefile.
- Local kind cluster work: `make -C kubernetes/kind help`.
- Local Lima cluster work: `make -C kubernetes/lima help`.
- Local Slicer cluster work: `make -C kubernetes/slicer help`.
- SD-WAN work: `make -C sd-wan/lima help`.

Read the nearest subtree `README.md` only after selecting the relevant path. Prefer the local `Makefile`, tests, and scripts over broad repo exploration.

Expect most stack workflows to require a platform env file. Run the subtree `prereqs` target before `plan` or `apply` when working under `kubernetes/*` or `sd-wan/*`. Bare root `make` should stay informational and should not fail on `PLATFORM_ENV_FILE`.

For non-interactive stack runs, use `AUTO_APPROVE=1`. `AUTO_APPLY` is not a supported flag in this repo.

Use these local cluster command paths when you need to prove a stack end to end instead of just reading docs:

- Kind full confidence path:
  `make -C kubernetes/kind reset AUTO_APPROVE=1`
  `make -C kubernetes/kind 100 apply AUTO_APPROVE=1`
  `make -C kubernetes/kind 900 apply AUTO_APPROVE=1`
  `make -C kubernetes/kind check-health`
- Lima conflict preflight while kind is still active:
  `make -C kubernetes/lima 900 apply AUTO_APPROVE=1`
  Expect this to fail fast in `check-kind-stopped` while `kind-local` is running; that is the validated guard before Lima reaches shared host-port checks.
- Lima clean confidence path after clearing both local targets:
  `make -C kubernetes/kind reset AUTO_APPROVE=1`
  `make -C kubernetes/lima reset AUTO_APPROVE=1`
  `make -C kubernetes/lima 100 apply AUTO_APPROVE=1`
  `make -C kubernetes/lima 900 apply AUTO_APPROVE=1`
  `make -C kubernetes/lima check-health`

When a long `apply` goes quiet, the default operator behavior is to keep waiting rather than interrupt it. These stacks can sit in long stretches of Argo reconciliation, Gitea bootstrap, gateway/TLS convergence, OIDC reconfiguration, or browser verification without printing much.

Do not treat “no new log lines for a while” as failure by itself. Prefer observing state from a second terminal while the original `apply` keeps running.

Use these state probes while an `apply` is in flight:

- Broad cluster convergence:
  `make -C kubernetes/kind check-health`
  `make -C kubernetes/lima check-health`
- Gateway/TLS-specific progress:
  `make -C kubernetes/kind check-gateway-stack`
  `make -C kubernetes/lima check-gateway-stack`
  `make -C kubernetes/kind check-gateway-urls`
  `make -C kubernetes/lima check-gateway-urls`
- SSO-specific progress:
  `make -C kubernetes/kind check-sso`
  `make -C kubernetes/lima check-sso`
  `make -C kubernetes/kind check-sso-e2e`
  `make -C kubernetes/lima check-sso-e2e`
- App-specific progress:
  `make -C kubernetes/kind check-app APP=<name>`
  `make -C kubernetes/lima check-app APP=<name>`
- Runtime/preflight state:
  `make -C kubernetes/kind status`
  `make -C kubernetes/lima status`
  `make -C kubernetes/lima proxy-status`
  `make -C kubernetes/kind audit-bootstrap`

Use the preflight checks to explain immediate failure modes instead of waiting on them:

- `make -C kubernetes/lima check-kind-stopped` tells you Lima is blocked because kind is still active.
- `make -C kubernetes/kind check-lima-stopped` and `make -C kubernetes/kind check-slicer-stopped` tell you kind is blocked by another local cluster target.

Rule of thumb: keep the original `apply` running until it either exits successfully or surfaces a concrete hard error. Use the `check-*` and `status` targets to understand what it is waiting for.

Use these landmarks when editing repo workflow behavior:

- `Makefile` for root routing/help behavior.
- `mk/common.mk` for shared make defaults and env checks.
- `tests/makefile.bats` for root make regressions.

When verifying work, use the smallest relevant surface:

- Repo-wide checks: `make lint`, `make fmt`.
- Root smoke for onboarding changes: `bats tests/makefile.bats`.
- Feature checks: `make -C <dir> test` or the nearest stack/app-specific validation target.

If you change onboarding, keep the path discoverable from a root file listing and keep the first command useful.
