---
name: use-platform
description: Orientation and workflow guide for the `platform` repository. Use when an agent is asked to work in a checkout of this repo, when the user mentions the platform repo or its local Kubernetes stacks, or when the agent needs to choose the correct Makefile, docs path, env-sensitive entrypoint, or verification command before making changes.
---

# Use Platform

Confirm the workspace root is the repository checkout that contains `Makefile`, `mk/`, `apps/`, and `kubernetes/`.

Start with the repo-local guidance and entrypoints, not the top-level README:

- Open `AGENTS.md` at the repo root.
- Run `make` or `make help` at the repo root.
- Treat root `make`, `make prereqs`, and `make test` as routing/help entrypoints. The mutating or repo-wide checks at the root are `make lint` and `make fmt`.

Choose the focused Makefile before reading deeper docs:

- App or frontend work: `make -C apps help` or the nearest app Makefile.
- Local kind cluster work: `make -C kubernetes/kind help`.
- Local Lima cluster work: `make -C kubernetes/lima help`.
- Local Slicer cluster work: `make -C kubernetes/slicer help`.

Read the nearest subtree `README.md` only after selecting the relevant path. Prefer the local `Makefile`, tests, and scripts over broad repo exploration.

Expect most stack workflows to require a platform env file. Run the subtree `prereqs` target before `plan` or `apply` when working under `kubernetes/*`. Bare root `make` should stay informational and should not fail on `PLATFORM_ENV_FILE`.

For non-interactive stack runs, use `AUTO_APPROVE=1`. `AUTO_APPLY` is not a supported flag in this repo.

Use the guided workflow surfaces when the user asks to operate the local stacks interactively, compare stage/app options, or see the exact command before running it:

- `make tui` opens the Bubble Tea terminal UI from `tools/platform-tui`. It requires Go because it runs the TUI from source. The TUI delegates to `scripts/platform-workflow.sh`, previews the generated Make command, can run it, streams output, keeps scrollback, and supports target, stage, action, reset, state-reset, and app toggle choices.
- `make build-tui` builds a local TUI binary under `tools/platform-tui/bin/` when you need a reusable executable.
- `make workflow-ui` serves the browser workflow UI from `tools/platform-workflow-ui` through `scripts/platform-workflow-ui.sh`. It requires `uv`, uses FastAPI + HTMX, defaults to local HTTPS at `https://console.127.0.0.1.sslip.io:8443`, and delegates to the same `scripts/platform-workflow.sh` core as the TUI.
- Use `make workflow-ui WORKFLOW_UI_HTTP=http1 WORKFLOW_UI_HOST=127.0.0.1 WORKFLOW_UI_PORT=8765` when local HTTPS or HTTP/2 gets in the way of browser debugging. Use `WORKFLOW_UI_PORT=<port>` when the default port is busy.
- Treat both guided surfaces as wrappers over the same contract, not separate deployment systems. If a preview looks wrong, inspect `scripts/platform-workflow.sh` and its tests before changing either UI.

Prefer the shared workflow core for automation and tests:

- Inspect choices:
  `scripts/platform-workflow.sh options --execute`
- Preview without mutating:
  `scripts/platform-workflow.sh preview --execute --target kind --stage 900 --action plan`
- Preview with generated app override tfvars:
  `scripts/platform-workflow.sh preview --execute --target kind --stage 900 --action apply --app sentiment=off`
- Run the selected workflow:
  `scripts/platform-workflow.sh apply --execute --target kind --stage 900 --action apply --auto-approve --app sentiment=off`

Generated operator tfvars paths in docs and examples should be relative to the repository root, such as `.run/operator/kind-stage900.tfvars`. Do not write user-specific absolute paths like `/Users/<name>/...` into docs, skills, or generated examples.

Use these local cluster command paths when you need to prove a stack end to end instead of just reading docs:

- Kind full confidence path:
  `make -C kubernetes/kind reset AUTO_APPROVE=1`
  `make -C kubernetes/kind 100 apply AUTO_APPROVE=1`
  `make -C kubernetes/kind 900 apply AUTO_APPROVE=1`
  `make -C kubernetes/kind check-health`
- The kind stage-900 browser path now runs inside the devcontainer too. The shared SSO harness maps `*.127.0.0.1.sslip.io` through `host.docker.internal` when `PLATFORM_DEVCONTAINER=1`, so the devcontainer can exercise the same `check-sso-e2e` step instead of skipping it.
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
- For kind stage-900 GitOps resources, remember that Argo CD normally reconciles from the in-cluster Gitea `platform/policies` repository, not directly from the working tree. Direct `kubectl apply` can be useful for diagnosis, but Argo self-heal may immediately restore the older rendered content. After changing Terraform-rendered GitOps manifests, run `make -C kubernetes/kind gitea-sync AUTO_APPROVE=1`, hard-refresh or wait for the relevant Argo app, then verify the live object. This matters especially for `cilium-policies`, `platform-gateway-routes`, APIM, SSO, and workload app manifests.
- If a live object does not match your working tree after `gitea-sync`, inspect the Argo app source path and revision first:
  `kubectl --kubeconfig ~/.kube/kind-kind-local.yaml --context kind-kind-local -n argocd get app <app> -o yaml`
  Then compare the rendered policy repo shape under the source path Argo uses, such as `cluster-policies/cilium` or `apps/<name>`.
- Review environments are platform substrate, not only a Backstage template concern. In kind, stage 900 should create the `review` namespace and `review/gitea-registry-creds` whenever Argo CD and Gitea are enabled, and the platform gateway certificate should include `*.review.127.0.0.1.sslip.io`. The scaffolded review workflow targets the in-cluster Gitea runner labels `self-hosted`, `in-cluster`, and `review-env`, then owns the per-branch Deployments, Services, CiliumNetworkPolicies, HTTPRoute, ReferenceGrant, and branch-delete cleanup. Do not paper over this with an `ubuntu-latest` alias; if generic hosted-runner compatibility becomes important, add a separate constrained CI runner instead of widening the deploy-capable runner. A review environment is expected only after a scaffolded Gitea repo receives a non-`main` branch push and an enabled in-cluster runner can pick up the workflow. Default `KIND_IMAGE_DISTRIBUTION_MODE=registry` still disables the runner path; use a runner-capable mode such as `load` or `baked` when you need to exercise actual Gitea Actions review-environment creation.
- When changing the Backstage/Portal image inputs, keep `kubernetes/kind/scripts/build-local-platform-images.sh` and `kubernetes/kind/scripts/render-operator-overrides.sh` source-fingerprint lists in sync. If the rendered external image tag and pushed image tag diverge, `idp/backstage` will go `ImagePullBackOff` on a source-hash tag even though `latest` exists.
- When changing Cilium policies in the kind GitOps path, validate both directions of a flow. A Gateway-to-APIM route, for example, needs platform-gateway egress to APIM and APIM ingress from platform-gateway; fixing only one side still looks like a timeout from the browser or curl.
- Protected API routes are allowed to be healthy by returning an auth failure. For machine API paths such as `https://mcp.127.0.0.1.sslip.io/mcp`, an unauthenticated `401` or `403` is the correct gateway smoke outcome; do not force those routes to behave like SSO browser pages that return `302`.
- If `make -C kubernetes/kind 900 apply AUTO_APPROVE=1` is interrupted during Terraform/OpenTofu, check for a zero-byte `terraform/.run/kubernetes/terraform.tfstate`. If the active state is empty and `terraform.tfstate.backup` is intact, restore the backup before rerunning. Do not use destructive reset commands unless the user explicitly asks.
- Kind can briefly show `nginx-gateway` instability during OIDC or apiserver reconfiguration and still recover cleanly. Treat the final `check-health` and `check-sso-e2e` results as the source of truth, not transient gateway pod restarts by themselves.
- The platform devcontainer now bakes Chromium runtime libraries, so the stage-900 kind path is no longer host-only. If browser E2E is failing inside the container, rebuild the devcontainer before assuming the stack is at fault.
- Inside the devcontainer, local HTTPS probes must target `host.docker.internal` instead of raw `127.0.0.1`. The devcontainer exports `PLATFORM_DEVCONTAINER_HOST_ALIAS` and `KIND_DEVCONTAINER_HOST_ALIAS` for this purpose, and the gateway/app/SSO checkers now honor those aliases.
- The managed kind kubeconfig is environment-sensitive: `ensure-kind-kubeconfig.sh` rewrites loopback API endpoints to `host.docker.internal` when `PLATFORM_DEVCONTAINER=1`, while the host shell keeps the raw loopback form. The shared `~/.kube/kind-kind-local.yaml` can therefore flip between two valid shapes as you move between shells, which can surface as non-no-op plans even though the cluster itself is unchanged.
- The devcontainer build only installs the repo toolchain if `.devcontainer/Dockerfile` invokes `install-toolchain.sh --execute`. If the build log prints the installer usage text and an `INFO dry-run` summary, the image is missing the actual CLI stack.
- Terragrunt runs the Kubernetes Terraform module from its cache copy, so any `path.module` references that reach back into `kubernetes/kind/` or `.run/kind/` must be replaced with absolute paths exported from the kind Makefile. The validated exports are `TF_VAR_kind_stage_900_tfvars_file`, `TF_VAR_kind_target_tfvars_file`, `TF_VAR_kind_stack_dir`, `TF_VAR_kind_config_path`, and `TF_VAR_kind_operator_overrides_file`.
- Terragrunt cache copies also break scripts that re-derive repo-root paths from `BASH_SOURCE[0]`. Terraform helper scripts under `terraform/kubernetes/` should honor an exported `REPO_ROOT` first, then fall back to their on-disk relative path only when the variable is unset.
- Lima can emit `Failed to allocate directory watch: Too many open files` while reconfiguring k3s OIDC and still complete successfully. If the apply, health checks, Argo sync, and SSO smoke pass afterward, treat that message as a rough edge rather than an automatic failure.
- Slicer currently assumes the local `~/slicer-mac/slicer-mac.yaml` host group matches the documented validated shape. In practice, `storage_size: 25G` for the `slicer` host group is required; smaller disks fail bootstrap because the root disk cannot be resized in place.
- If Headlamp SSO fails on Slicer with `Headlamp did not establish an authenticated Kubernetes session`, inspect `/etc/rancher/k3s/config.yaml.d/90-headlamp-oidc.yaml` inside the VM and `journalctl -u k3s`. Repeated `invalid bearer token` errors there mean the apiserver OIDC config did not land or is wrong.
- Slicer daemon startup can fail on a stale `~/slicer-mac/slicer.sock` even when the socket file still exists. The validated debugging path is `make -C kubernetes/slicer daemon-up`, `make -C kubernetes/slicer status`, and, if needed, `kubernetes/slicer/.run/slicer-mac.log`. Do not assume “socket file exists” means the daemon is healthy.
- After a forced host stop or obviously corrupted Slicer restart, keep the default repo reset conservative and use the heavier image prune only as an explicit troubleshooting step. The validated recovery path was either `make -C kubernetes/slicer reset AUTO_APPROVE=1 SLICER_RESET_PRUNE_ALL_IMAGES=1` or the equivalent manual flow: `~/slicer-mac/slicer-mac service stop daemon`, delete `~/slicer-mac/*.img`, then `~/slicer-mac/slicer-mac service start daemon` before rerunning `make -C kubernetes/slicer 100 apply AUTO_APPROVE=1`. Deleting only `slicer-1*.img` was not sufficient in the validated forced-stop recovery because the corrupted base image also had to be pruned.
- A fresh Slicer `900 apply` can decide `slicer-k3s not reachable; bootstrapping via STAGE=100` even right after a manual `100 apply`. That fallback is part of the wrapper behavior; let it continue unless it surfaces a concrete hard error.

When adding a new internal platform workload:

- Follow the existing hardened-container pattern before accepting new code. Prefer DHI runtime images where the repo already uses them, keep runtime dependencies minimal and pinned, honor the repository cooldown policy, drop Linux capabilities, run as non-root, disable service account token mounting unless needed, and use read-only root filesystems with explicit writable temp/cache volumes.
- For Python services, keep startup cheap. Missing optional upstream configuration, credentials, or runtime tools should surface as structured recoverable request/tool errors instead of import-time failures that prevent discovery, health checks, or `tools/list`.
- Give local images content-addressed tags in the kind image override path when rollout correctness depends on source changes. A stable `latest` tag can leave Kubernetes running an older image because the Deployment template did not change.
- Add `/health` or the repo-standard readiness endpoint before wiring Kubernetes probes. Confirm the live container serves that path, not just the local test server.
- Make observability part of the first pass: structured logs to stdout for VictoriaLogs, Prometheus scrape annotations or scrape config for metrics, Grafana dashboards/links, and OTel environment variables where the stack already expects them.
- Make Backstage discovery part of the first pass: catalog entities, `backstage.io/kubernetes-label-selector`, platform app inventory, endpoint/console/Grafana links, and workload labels that match the selectors.

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
