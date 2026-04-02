# Platform

Infrastructure and platform-engineering experiments, grouped by outcome first
and implementation second.

## Dependency cooldown policy

This repository intentionally carries project-local dependency age gates rather
than relying only on operator-level dotfiles such as `~/.npmrc`,
`~/.bunfig.toml`, or `~/.config/uv/uv.toml`.

That is deliberate for two reasons:

- container builds do not automatically inherit the host user's home-directory
  package-manager config
- people may copy an individual app subtree out of [`./apps`](apps) and still
  expect the same dependency hardening defaults

The current repo policy is a seven-day cooldown for newly published packages:

- JavaScript package roots ship local `bunfig.toml` with
  `minimumReleaseAge = 604800`
- JavaScript package roots also ship local `.npmrc` with
  `min-release-age=7`
- Python app roots that resolve with `uv` set
  `[tool.uv].exclude-newer = "7 days"` in `pyproject.toml`
- Bun-based Dockerfiles copy `bunfig.toml` into the image before `bun install`,
  so `docker compose` and standalone image builds keep the same cooldown

The Python dependency path in this repo is `uv`, not `pip`, so the repo bakes
the age gate into `pyproject.toml` for `uv`-managed apps.

Practical consequence: if you run a local install or image build in this repo,
or copy one of the app directories and build it elsewhere, dependency
resolution should still reject packages published within the last seven days
unless you intentionally override that policy.

## Devcontainer

There is an Ubuntu 24.04 devcontainer in
[`./.devcontainer`](.devcontainer) for the Linux-friendly repo workflows.

It uses the official devcontainers base image, shares the host Docker socket,
and installs the repo toolchain with a Linux-first split: `apt` for distro
packages, devcontainer features for Docker/Node integration, upstream
installers for a few standalone CLIs, and `arkade` for the Kubernetes tooling.

The container now also includes `kubie` for split-kubeconfig context work and
`starship`, seeded from
[`./.devcontainer/starship.toml`](.devcontainer/starship.toml).

That means `docker`, `kind`, and `docker compose` inside the devcontainer act
on the same local Docker daemon as the host shell, so repo workflows behave
the same way without special-case Makefile logic.

For the `kubernetes/kind` workflow, the repo’s kubeconfig helper rewrites the
kind API endpoint to `host.docker.internal` inside the devcontainer so
`kubectl`, OpenTofu, and Helm can still reach the host-exposed API server.

Repo-owned kubeconfigs now stay split by default, so `kubie lint` and `kubie`
context commands can work across `~/.kube/*.yaml` without the repo also
duplicating those contexts into `~/.kube/config`. If you want the older merged
shape for a specific workflow, each cluster Makefile exposes an explicit
`merge-default-kubeconfig` target.

From the host, the main devcontainer entrypoints are:

```shell
make -C .devcontainer prereqs
make -C .devcontainer build
make -C .devcontainer run
make -C .devcontainer exec
```

`build` removes the existing workspace container before rebuilding the image.
`run` starts the container without attaching a shell. `exec` and `up` ensure
the container is running and then attach a shell. None of them force another
rebuild.

After the container starts, the main in-container verification entrypoints are:

```shell
make lint
make -C apps prereqs
make -C kubernetes/kind prereqs
make -C apps/subnet-calculator/frontend-typescript-vite prereqs
```

For the actual startup flow, including the VS Code path versus the Dev
Container CLI path, see
[`./.devcontainer/README.md`](.devcontainer/README.md).

Limits:

- `sd-wan/lima` remains macOS-only by design.
- `kubernetes/lima` includes `limactl` in the container, but nested Lima VM
  workflows still depend on host virtualization rather than the devcontainer.
- `kubernetes/slicer` expects `SLICER_URL` or `SLICER_SOCKET` to point at a
  reachable Slicer endpoint, because the personal `slicer-mac` socket is not
  present inside the container. The same limit means the `kubernetes/kind`
  Slicer conflict check only sees a Slicer daemon if you deliberately surface
  that socket into the container.

## Repo validation

From the project root:

```shell
make lint
make fmt
```

`make lint` is reporting-only. It runs recursive YAML linting using
[`./.yamllint`](.yamllint), tracked-file Markdown linting using
[`./.markdownlint`](.markdownlint) when a Markdown linter is available, the
repo's static Cilium policy validation pass, and checked-in Kyverno policy test
suites.

`make fmt` is the mutating path. Today it applies tracked-file Markdown
auto-fixes when a Markdown linter is available.

Shell entrypoints follow the shared safety/interface contract documented in
[`docs/shell-entrypoint-standards.md`](docs/shell-entrypoint-standards.md).
Repo-owned callers now pass explicit `--execute` or `--dry-run` when they
invoke shell entrypoints. Bare invocation is preview-only and prints help plus
dry-run output instead of running live.

For live cluster-side validation against the current kubeconfig context:

```shell
make lint-cilium-live
make lint-kyverno-live
```

The current Cilium toolchain in this repo does not expose a `cilium policy
validate` file-mode command, so `make lint-cilium-live` runs
`cilium-dbg preflight validate-cnp` using a local `cilium-dbg` when present,
otherwise through a running in-cluster Cilium agent, and finally through the
matching Cilium image when Docker is available.

Kyverno's local repo-side validation uses `kyverno test`, and the optional live
cluster-side pass uses `kyverno apply --cluster --policy-report` against the
rendered in-repo policies.

## Local Kubernetes in Docker cluster

I spent several months making a "useful to me" local kubernetes cluster using
kind (Kubernetes IN Docker):

From the project root:

```shell
make -C kubernetes/kind prereqs
make -C kubernetes/kind 900 plan
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind 900 check-health
make -C kubernetes/kind 900 check-health DRY_RUN=1
```

Stages are cumulative: `100` creates the cluster, `900` brings up the full
local platform stack, but you could apply `500` if you "only" wanted Cilium,
Hubble, ArgoCD, and Gitea running in-cluster.

The stage-first positional Make syntax remains supported, for example
`make -C kubernetes/kind 100 apply`. Under the hood, the Makefile now forwards
named flags such as `--execute`, `--dry-run`, and repeated `--var-file`
arguments to the underlying scripts.

At stage `900`, the Make-based `apply` path now also runs the repo health check
and browser SSO E2E verification before it returns success. A raw
Terraform/OpenTofu apply still remains a strict apply-only path.

See [kubernetes/kind/README.md](kubernetes/kind/README.md) for the stage
model, prerequisites, diagrams, ports, and troubleshooting.

## Local Kubernetes on Lima virtual machines

There is also a fallback path for the same platform stack on a k3s cluster
running inside Lima virtual machines:

```shell
make -C kubernetes/lima prereqs
make -C kubernetes/lima 100 apply
make -C kubernetes/lima 900 plan
make -C kubernetes/lima 900 apply AUTO_APPROVE=1
make -C kubernetes/lima 900 check-health
make -C kubernetes/lima 900 check-health DRY_RUN=1
```

This keeps the same cumulative stage ladder as `kubernetes/kind`, but stage
`100` bootstraps k3s on Lima and stages `200+` apply the shared Terraform stack
against that kubeconfig-backed cluster through the Lima target profile. At
stage `900`, the Make-based `apply` path also runs the repo health check and
browser SSO E2E verification before it returns success.

See [kubernetes/lima/README.md](kubernetes/lima/README.md) for the Lima
workflow, prerequisites, and operator targets.

## Local Kubernetes on Slicer microVMs

There is also a Slicer-backed path in the repository.

As of March 14, 2026, a fresh `slicer-1` built from the on-device
[`~/slicer-mac/slicer-mac.yaml`](/Users/nickromney/slicer-mac/slicer-mac.yaml)
image can complete stages `100` through `900`, including Cilium, Hubble, Argo
CD, Gitea, and Dex SSO, provided the VM has enough disk. The validated shape
for that run was `8GiB` RAM and a `25G` root disk.

The intended operator shape is:

```shell
export SLICER_VM_GROUP=slicer
make -C kubernetes/slicer prereqs
make -C kubernetes/slicer 100 apply
make -C kubernetes/slicer 900 plan
make -C kubernetes/slicer 900 apply AUTO_APPROVE=1
make -C kubernetes/slicer 900 check-health
make -C kubernetes/slicer 900 check-health DRY_RUN=1
```

At stage `900`, the Make-based `apply` path also runs the repo health check and
browser SSO E2E verification before it returns success. A raw
Terraform/OpenTofu apply remains apply-only.

This keeps the same cumulative stage ladder as `kubernetes/kind`, but stage
`100` bootstraps k3s on Slicer and stages `200+` apply the shared Terraform
stack against that kubeconfig-backed cluster.

One Slicer-specific detail: the localhost HTTPS gateway uses `:8443`, so
browser URLs are `https://*.127.0.0.1.sslip.io:8443/...` rather than bare
`443`.

See [kubernetes/slicer/README.md](kubernetes/slicer/README.md) for the current
status, host-forwarding model, and operator targets.

## SD-WAN 3-cloud simulation, on Lima Virtual Machines

This was a thought experiment of whether I could use Lima virtual machines to
simulate public clouds, where the RFC1918 ranges "mean" something different
dependent on context, showing how a frontend served from cloud1 can consume an
API served from cloud2.

```shell
make -C sd-wan/lima prereqs
make -C sd-wan/lima up
make -C sd-wan/lima show-urls
make -C sd-wan/lima test
```

Expected outcome: open the frontend URL from
`make -C sd-wan/lima show-urls`, then run a lookup and compare the
`Frontend Diagnostics (cloud1 viewpoint)` and
`Backend Diagnostics (cloud2 viewpoint)` panels.

See [sd-wan/lima/README.md](sd-wan/lima/README.md) for the lab walkthrough,
topology notes, and browser checks.

## Plans

Over time, this repository is likely to contain groupings by

Public clouds:

- aws
- azure

Technologies:

- kubernetes
- sd-wan

Tooling:

- lima (virtual machines on Mac)
- slicer (micro VMs on Linux and Mac)

## Project docs

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [AI_POLICY.md](AI_POLICY.md)
- [LICENSE.md](LICENSE.md)

## License

This repository is source-available under the Functional Source License 1.1,
with MIT as the future licence.

In practical terms, the code is here so you can read it, learn from it, run
it, and adapt it for permitted purposes. What you cannot do during the first
two years after a given version is published is turn that version into a
competing commercial product or service. After that two-year delay, that
version becomes available under MIT.

The intent of this licence choice is simple: people should be able to learn
from the examples and projects in this repository without using them as a
shortcut to run a competing commercial operation during the delayed-open
period.

This summary is informational only. The actual legal terms are in
[LICENSE.md](LICENSE.md).
