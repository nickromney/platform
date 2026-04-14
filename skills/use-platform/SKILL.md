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
- Slicer clean confidence path after clearing the other local targets:
  `make -C kubernetes/lima reset AUTO_APPROVE=1`
  `make -C kubernetes/slicer reset AUTO_APPROVE=1`
  `make -C kubernetes/slicer 100 apply AUTO_APPROVE=1`
  `make -C kubernetes/slicer 900 apply AUTO_APPROVE=1`
  `make -C kubernetes/slicer check-health`

Validated operator learnings from real teardown/rebuild runs:

- Prefer the split kubeconfigs over `~/.kube/config` when debugging standalone helpers. The validated paths are `~/.kube/kind-kind-local.yaml`, `~/.kube/limavm-k3s.yaml`, and `~/.kube/slicer-k3s.yaml`. If the default kubeconfig has no current context, pass both `KUBECONFIG_PATH` and `KUBECONFIG_CONTEXT` instead of assuming `kubectl config current-context` will succeed.
- Kind can briefly show `nginx-gateway` instability during OIDC or apiserver reconfiguration and still recover cleanly. Treat the final `check-health` and `check-sso-e2e` results as the source of truth, not transient gateway pod restarts by themselves.
- Lima can emit `Failed to allocate directory watch: Too many open files` while reconfiguring k3s OIDC and still complete successfully. If the apply, health checks, Argo sync, and SSO smoke pass afterward, treat that message as a rough edge rather than an automatic failure.
- Slicer currently assumes the local `~/slicer-mac/slicer-mac.yaml` host group matches the documented validated shape. In practice, `storage_size: 25G` for the `slicer` host group is required; smaller disks fail bootstrap because the root disk cannot be resized in place.
- If Headlamp SSO fails on Slicer with `Headlamp did not establish an authenticated Kubernetes session`, inspect `/etc/rancher/k3s/config.yaml.d/90-headlamp-oidc.yaml` inside the VM and `journalctl -u k3s`. Repeated `invalid bearer token` errors there mean the apiserver OIDC config did not land or is wrong.
- Slicer daemon startup can fail on a stale `~/slicer-mac/slicer.sock` even when the socket file still exists. The validated debugging path is `make -C kubernetes/slicer daemon-up`, `make -C kubernetes/slicer status`, and, if needed, `kubernetes/slicer/.run/slicer-mac.log`. Do not assume “socket file exists” means the daemon is healthy.
- After a forced host stop or obviously corrupted Slicer restart, keep the default repo reset conservative and use the heavier image prune only as an explicit troubleshooting step. The validated recovery path was either `make -C kubernetes/slicer reset AUTO_APPROVE=1 SLICER_RESET_PRUNE_ALL_IMAGES=1` or the equivalent manual flow: `~/slicer-mac/slicer-mac service stop daemon`, delete `~/slicer-mac/*.img`, then `~/slicer-mac/slicer-mac service start daemon` before rerunning `make -C kubernetes/slicer 100 apply AUTO_APPROVE=1`. Deleting only `slicer-1*.img` was not sufficient in the validated forced-stop recovery because the corrupted base image also had to be pruned.
- A fresh Slicer `900 apply` can decide `slicer-k3s not reachable; bootstrapping via STAGE=100` even right after a manual `100 apply`. That fallback is part of the wrapper behavior; let it continue unless it surfaces a concrete hard error.

When a long `apply` goes quiet, the default operator behavior is to keep waiting rather than interrupt it. These stacks can sit in long stretches of Argo reconciliation, Gitea bootstrap, gateway/TLS convergence, OIDC reconfiguration, or browser verification without printing much.

Do not treat “no new log lines for a while” as failure by itself. Prefer observing state from a second terminal while the original `apply` keeps running.

Use these state probes while an `apply` is in flight:

- Broad cluster convergence:
  `make -C kubernetes/kind check-health`
  `make -C kubernetes/lima check-health`
  `make -C kubernetes/slicer check-health`
- Gateway/TLS-specific progress:
  `make -C kubernetes/kind check-gateway-stack`
  `make -C kubernetes/lima check-gateway-stack`
  `make -C kubernetes/slicer check-gateway-stack`
  `make -C kubernetes/kind check-gateway-urls`
  `make -C kubernetes/lima check-gateway-urls`
  `make -C kubernetes/slicer check-gateway-urls`
- SSO-specific progress:
  `make -C kubernetes/kind check-sso`
  `make -C kubernetes/lima check-sso`
  `make -C kubernetes/slicer check-sso`
  `make -C kubernetes/kind check-sso-e2e`
  `make -C kubernetes/lima check-sso-e2e`
  `make -C kubernetes/slicer check-sso-e2e`
- App-specific progress:
  `make -C kubernetes/kind check-app APP=<name>`
  `make -C kubernetes/lima check-app APP=<name>`
  `make -C kubernetes/slicer check-app APP=<name>`
- Runtime/preflight state:
  `make -C kubernetes/kind status`
  `make -C kubernetes/lima status`
  `make -C kubernetes/slicer status`
  `make -C kubernetes/lima proxy-status`
  `make -C kubernetes/kind audit-bootstrap`

Use the preflight checks to explain immediate failure modes instead of waiting on them:

- `make -C kubernetes/lima check-kind-stopped` tells you Lima is blocked because kind is still active.
- `make -C kubernetes/kind check-lima-stopped` and `make -C kubernetes/kind check-slicer-stopped` tell you kind is blocked by another local cluster target.
- `make -C kubernetes/slicer check-kind-stopped` and `make -C kubernetes/slicer check-lima-stopped` tell you Slicer is blocked by another local cluster target.

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
