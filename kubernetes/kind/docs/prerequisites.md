# Prerequisites

This kind path is the repo's Docker-backed teaching target.

Supported host shapes: any host with a reachable Docker daemon. The daemon
flavour does not matter — Docker Desktop, colima, OrbStack, and plain Docker
Engine all work on both macOS and Linux.

## Install

Install a working Docker daemon first.

- macOS: Docker Desktop is the usual choice, but Docker Engine via colima or
  OrbStack works just as well.
- Debian/Ubuntu: `sudo apt-get install docker.io`.
- Arch/Omarchy: `sudo pacman -S --needed docker`, then
  `sudo systemctl enable --now docker.socket` so the daemon starts on demand.

Then install the CLI tools. Rather than copying the lists below by hand, ask
the repo what is missing on this host and how to install it:

```bash
make -C kubernetes/kind prereqs
```

`prereqs` names every missing tool and prints an install command tailored to
the managers you actually have. It prefers `mise`, because mise installs the
same versions on macOS and Linux and pins them to the versions in
`.devcontainer/toolchain-versions.sh` that this repo was validated against.
Hints are deliberately repo-scoped (`mise use`, not `mise use -g`), so the
platform writes its pins to `./mise.toml` and never edits your global tool
config.

The manager preference order is mise, Homebrew, pacman, apt, arkade, curl.
Everything above arkade has a one-command upgrade path; arkade pins a binary
with no upgrade sweep, so it is used only for tools the others do not carry.
Override the order with `INSTALL_TOOL_HINTS_MANAGERS`, for example
`INSTALL_TOOL_HINTS_MANAGERS="pacman curl"`.

The Homebrew lists below still work on macOS and Ubuntu if you prefer them.

Core tools:

```bash
brew install jq kind kubernetes-cli make opentofu terragrunt
```

Browser/E2E tools:

```bash
brew install bun node
```

On the host, `make -C kubernetes/kind 900 apply` runs `check-sso-e2e` before it
returns success, so `bun` and `node` are required for the host stage-900
Makefile path.
`node` provides `npm` and `npx`; Playwright stays project-local in the repo.

Optional tools:

```bash
brew install cilium-cli helm hubble kubectx kubie kyverno mkcert yq
mkcert -install
```

If you install Homebrew `make`, the binary is `gmake` unless you add GNU Make's `gnubin` directory to `PATH`.

## Registry Auth

The shipped kind path uses Docker Hardened Images from `dhi.io` for Argo CD,
Kyverno, cert-manager, parts of observability, and some support images. On a
fresh host, authenticate Docker before you expect those images to pull:

```bash
docker login dhi.io
```

If you also rely on Docker Hub pulls outside the Desktop sign-in flow, make
sure those credentials are available too:

```bash
docker login
```

## What The Core Tools Do

- `make` runs the workflow entrypoints in [`Makefile`](../Makefile).
- The Docker daemon plus the `docker` CLI runs the kind node containers.
- `jq` is used by the health and audit scripts.
- `kubectl` talks to the cluster during applies and checks.
- `kind` creates and deletes the local cluster.
- OpenTofu (`tofu`) runs the Terraform-compatible infrastructure plan.
- `terragrunt` provides the wrapper layer over that OpenTofu/Terraform stack.
- `bun` runs the checked-in stage-900 SSO E2E harness.
- `node` provides the runtime plus `npm`/`npx` for browser tooling.

## What The Optional Tools Do

- `cilium` is useful for manual Cilium inspection and troubleshooting.
- `hubble` is useful for manual flow inspection once stage `300` is up.
- `helm` is useful for version and chart debugging.
- `kubectx` is just a convenience tool for context switching when you have
  intentionally merged a repo kubeconfig into `~/.kube/config`.
- `kubie` is useful for linting and switching across the repo's split
  kubeconfig files.
- `kyverno` is useful for local and live Kyverno policy validation via the
  root `make lint`, `make lint-kyverno`, and `make lint-kyverno-live` paths.
- `mkcert` is useful once HTTPS and local trust matter.
- `yq` is helpful for ad hoc YAML inspection while debugging.

## What `make prereqs` Checks

`make prereqs` is the fastest sanity check after installation. It verifies:

- expected binaries are on `PATH`
- optional repo-validation tools such as `yamllint`, `cilium`, and `kyverno`
  are surfaced with their current host visibility
- stage-aware browser/E2E tools such as `bun`, `node`, `npm`, and `npx` are
  required from stage `900`, and are otherwise surfaced as recommended tooling
  with install hints when missing
- the Docker daemon is reachable through `docker info`
- Docker auth status is visible for `dhi.io` and Docker Hub
- versions for the main tools can be queried
- kubeconfig files and contexts look sane

By default the repo keeps its own kubeconfigs split, for example
`~/.kube/kind-kind-local.yaml`. If you need a legacy merged shape for a tool
that only reads `~/.kube/config`, use `make merge-default-kubeconfig`
explicitly rather than relying on the repo to auto-merge.

Read-only operator targets now invoke their backing scripts with explicit
`--execute` flags. To preview the same checks without running them, keep the
same Make target shape and add `DRY_RUN=1`, for example:

```bash
make 900 check-health DRY_RUN=1
```

Run it from this directory with:

```bash
make prereqs
```

## Sentiment Runtime Requirement

The shipped sentiment demo runs the Go lexicon classifier in-process inside
`sentiment-api`, so the default kind path does not require any host-side LLM
endpoint.
