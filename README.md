# Platform

Local platform-engineering labs centered on one primary operator outcome:
bring up a useful Kubernetes stack on a laptop or workstation.

The main path in this repository is [`kubernetes/kind`](kubernetes/kind),
which takes a local cluster from a bare kind bootstrap to Cilium, Hubble,
Argo CD, Gitea, policy enforcement, observability, gateway TLS, and SSO.

## Start Here

The root `Makefile` is intentionally informational. Use it as a router, then
drop into the focused workflow:

```shell
make
make -C kubernetes/kind help
```

If you want the default local platform path, start with `kubernetes/kind`:

```shell
cp .env.example .env
make -C kubernetes/kind prereqs
make -C kubernetes/kind 100 plan
make -C kubernetes/kind 100 apply AUTO_APPROVE=1
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind 900 check-health
make -C kubernetes/kind show-urls
```

Common rebuild loop:

```shell
make -C kubernetes/kind reset AUTO_APPROVE=1
make -C kubernetes/kind 100 apply AUTO_APPROVE=1
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
```

Important operator notes:

- Stage `100` is intentionally not fully healthy yet. The cluster exists, but
  Cilium does not arrive until stage `200`.
- Stages are cumulative. `900` means "bring the cluster to the full-stack
  shape", not "apply only the last step".
- The repo-owned kubeconfig defaults to `~/.kube/kind-kind-local.yaml`.
- On macOS the normal host runtime is Docker Desktop. On Linux, Docker Engine
  or Docker Desktop is fine.
- `make -C kubernetes/kind reset AUTO_APPROVE=1` is destructive local cleanup.

Read [kubernetes/kind/README.md](kubernetes/kind/README.md) for the full stage
ladder, host ports, architecture notes, and troubleshooting details.

## What Kind Gives You

The stage ladder is cumulative:

- `100`: kind cluster bootstrap
- `200`: Cilium as the CNI
- `300`: Hubble
- `400`: Argo CD core
- `500`: Gitea plus the full Argo CD controller set
- `600`: Kyverno, cert-manager, and Cilium policy controls
- `700`: app repos and the in-cluster Actions runner
- `800`: gateway TLS, Headlamp, Grafana, Prometheus, and Loki
- `900`: Keycloak and `oauth2-proxy` single sign-on

## Choose A Path

| If you want... | Go here | First command |
| --- | --- | --- |
| The main local Kubernetes workflow | [`kubernetes/kind`](kubernetes/kind) | `make -C kubernetes/kind help` |
| The same stack on Lima VMs | [`kubernetes/lima`](kubernetes/lima) | `make -C kubernetes/lima help` |
| The same stack on Slicer microVMs | [`kubernetes/slicer`](kubernetes/slicer) | `make -C kubernetes/slicer help` |
| App and frontend work | [`apps`](apps) | `make -C apps help` |
| Docker Compose experiments | [`docker/compose`](docker/compose) | `make -C docker/compose help` |
| The SD-WAN lab | [`sd-wan/lima`](sd-wan/lima) | `make -C sd-wan/lima help` |

The most important secondary app path is
[`apps/subnetcalc`](apps/subnetcalc), which supplies the sample
workloads used by the local cluster stack.

## Repo-Level Commands

From the repository root:

```shell
make
make lint
make fmt
make check-version
make release-dry-run VERSION=0.3.0
make release-tag VERSION=0.3.0
```

Notes:

- `make` is a guide, not a mutating entrypoint.
- `make prereqs` and `make test` at the root are also informational. They tell
  you which focused subtree command to run next.
- `make lint` is the repo-wide reporting pass.
- `make fmt` applies the tracked markdown formatting pass.
- `make check-version` verifies the root workflow pins, the vendored
  `apim-simulator` tag/SHA metadata, and the repo-local dependency age gates
  for npm, Bun, and uv-managed Python roots.
  Prerelease channels stay off by default; opt in with
  `CHECK_VERSION_INCLUDE_CANARY=1`, `CHECK_VERSION_INCLUDE_ALPHA=1`, or
  `CHECK_VERSION_INCLUDE_PRERELEASE=1` when you explicitly want canary, alpha,
  beta, dev, preview, rc, or next versions considered.
- `make release VERSION=X.Y.Z` updates the root `VERSION` marker, runs the
  release gate, and creates a reviewable release commit.
- `make release-dry-run VERSION=X.Y.Z` previews that release-commit flow. The
  older `make release-preview VERSION=X.Y.Z` alias still works.

## Validation And Supporting Workflows

Useful references once the kind path is working:

- [`docs/prerequisites.md`](docs/prerequisites.md) for toolchain expectations
- [`docs/tooling.md`](docs/tooling.md) for the Terraform, Terragrunt, and
  kubeconfig model
- [`terraform/kubernetes/docs/README.md`](terraform/kubernetes/docs/README.md)
  for the shared stack internals
- [`apps/subnetcalc/README.md`](apps/subnetcalc/README.md) for
  the main sample application workflow

## Devcontainer

There is an Ubuntu 24.04 devcontainer in
[`./.devcontainer`](.devcontainer) for Linux-friendly repo workflows.

Start with:

```shell
make -C .devcontainer prereqs
make -C .devcontainer build
make -C .devcontainer exec
```

The full setup and host-versus-container behavior are documented in
[`.devcontainer/README.md`](.devcontainer/README.md).

## Dependency Cooldown Policy

This repo intentionally keeps dependency age gates in-repo so the same safety
floor applies to host installs, container builds, and copied subtrees.

- Bun roots use local `bunfig.toml` with `minimumReleaseAge = 604800`
- npm roots use local `.npmrc` with `min-release-age=7`
- `uv`-managed Python roots use `[tool.uv].exclude-newer = "7 days"`
- Dockerfiles copy those local configs so image builds keep the same policy
