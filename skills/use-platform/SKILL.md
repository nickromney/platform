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

Use these landmarks when editing repo workflow behavior:

- `Makefile` for root routing/help behavior.
- `mk/common.mk` for shared make defaults and env checks.
- `tests/makefile.bats` for root make regressions.

When verifying work, use the smallest relevant surface:

- Repo-wide checks: `make lint`, `make fmt`.
- Root smoke for onboarding changes: `bats tests/makefile.bats`.
- Feature checks: `make -C <dir> test` or the nearest stack/app-specific validation target.

If you change onboarding, keep the path discoverable from a root file listing and keep the first command useful.
