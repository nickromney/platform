# Devcontainer

This repo ships a devcontainer for the Linux-friendly workflows in the
repository. It is based on Ubuntu 24.04 and is intended to run the same
`make prereqs` entrypoints as the host, without special-case Make logic.

## Host Entry Points

From the repo root, the supported wrapper flow is:

```bash
make -C .devcontainer prereqs
make -C .devcontainer build
make -C .devcontainer run
make -C .devcontainer exec
```

Those targets use the Dev Container CLI against the repo root. They exist so
you do not have to remember the raw `devcontainer ...` commands or rely on the
VS Code UI to discover the right path.

`build` removes any existing workspace container for this repo before it builds
the image, so a later `run` cannot silently reattach to a stale container.
`run` does not rebuild the image and does not attach a shell; it only starts
the current workspace container, or creates one from the already-built image if
needed. `exec` and `up` both ensure the container is running and then attach a
login shell. `run`, `exec`, and `up` are host-side entrypoints. If you are
already inside the devcontainer, use the current shell rather than calling them
again.

## What It Depends On

The devcontainer is not tied to Docker Desktop itself. It needs two things:

1. A Docker-compatible local daemon.
2. A devcontainer client.

The usual combinations are:

- macOS: Docker Desktop plus the VS Code Dev Containers extension.
- Linux: Docker Engine or Docker Desktop plus the VS Code Dev Containers
  extension.
- Terminal-only: the Dev Container CLI against a local Docker daemon.

Docker Desktop provides the Docker Engine, CLI, and Compose on macOS and
Windows. VS Code is what gives you the "open this folder in the devcontainer"
experience.

`make -C .devcontainer prereqs` checks:

- a reachable Docker-compatible daemon
- the `devcontainer` CLI
- the VS Code Dev Containers extension via `code --list-extensions` when the
  editor CLI is available
- the host mount directories used by this repo's `devcontainer.json`

If you use a VS Code-compatible editor with a different CLI name, override
`VSCODE_BIN`, for example:

```bash
make -C .devcontainer prereqs VSCODE_BIN=cursor
```

## Recommended Start Path

This is the first-class path for this repo.

1. Run `make -C .devcontainer prereqs`.
2. Open this repository in VS Code.
3. Run `Dev Containers: Open Folder in Container...` from the Command Palette.
   If the folder is already open, `Dev Containers: Reopen in Container` is
   equivalent.
4. Wait for the image build and post-create setup to finish.
5. Verify the toolchain from inside the container:

```bash
make -C apps prereqs
make -C kubernetes/kind prereqs
```

## Terminal-Only Start Path

If you do not want to use VS Code, the wrapper Makefile is the intended path:

```bash
make -C .devcontainer prereqs
make -C .devcontainer build
make -C .devcontainer run
make -C .devcontainer exec
```

`build` is the clean-image path. It evicts the existing workspace container
first, then builds the image. `run` starts the devcontainer without attaching a
shell. `exec` and `up` are the “ensure running, then enter it” paths.

The VS Code extension check is informational for this CLI-only path. If you
want the raw commands instead, use the Dev Container CLI directly:

1. Install the CLI:

See the [Dev Container CLI docs](https://code.visualstudio.com/docs/devcontainers/devcontainer-cli)
for the official installation routes, or the
[Homebrew formula](https://formulae.brew.sh/formula/devcontainer) if you use
Homebrew.

```bash
brew install devcontainer
```

If you are not using Homebrew, the official npm package is:

```bash
npm install -g @devcontainers/cli
```

If you already use the VS Code extension, you can also install the same CLI from
the Command Palette with `Dev Containers: Install devcontainer CLI`.

1. Verify the CLI is available:

```bash
devcontainer --version
```

1. Start and enter the container:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . zsh
```

That uses the same `.devcontainer/devcontainer.json` definition as VS Code.

## Tooling Notes

For kind/OpenTofu parity, the devcontainer intentionally reuses the host's
absolute workspace path and bind-mounts the host `~/.kube` directory into the
container twice:

- at the host path itself, so Terraform/OpenTofu state that records absolute
  paths does not drift between host and devcontainer
- at `/home/vscode/.kube`, so normal shell tools such as `kubectl` and `kubie`
  still find kubeconfigs on their default Linux paths

That is why `make -C kubernetes/kind 900 plan` can compare cleanly with a host
apply without special-case Makefile logic.

The devcontainer also mounts a host staging directory at
`~/.config/platform-devcontainer/mkcert` into `/home/vscode/.mkcert`. The
wrapper `make prereqs` target creates that staging directory and, when `mkcert`
is installed on the host, syncs the current host CA contents into it. That
avoids a hard dependency on a macOS-specific mkcert path while still letting
the container reuse the host CA when available.

The devcontainer now follows a Linux-first toolchain split:

- `apt`: base Linux packages such as `bats`, `neovim`, `shellcheck`, and
  `yamllint`
- devcontainer features: Docker socket integration and Node.js 24
- upstream installers: `bun`, `starship`, `step`, `kyverno`, and `lima`
- direct binary copy: `uv`
- `arkade`: Kubernetes-facing tools such as `kubectl`, `kind`, `helm`,
  `cilium`, `hubble`, `k3sup`, `kubie`, `terragrunt`, `tofu`, and the local
  `slicer` helper

The repo-level `make lint` entrypoint works inside the devcontainer too, and
the image includes both `yamllint` and `kyverno` for the recursive YAML and
local policy validation passes.

It also seeds shell startup for both `bash` and `zsh` so the container has:

- `EDITOR=nvim` and `VISUAL=nvim`
- a visible `devcontainer` prompt badge, so it is clear when your shell is
  already attached to the container
- `node`, `npm`, `npx`, and `bun` for local JavaScript tooling and repo scripts
- generated completion scripts for `kubectl`, `kubie`, `kind`, `helm`,
  `cilium`, and `hubble` when those binaries are present
- `starship` prompt init in both shells

It also seeds:

- `~/.config/starship.toml` from
  [`starship.toml`](./starship.toml)
- managed shell includes sourced from `~/.bashrc` and `~/.zshrc`

For editing inside the container, the image installs `neovim`, and post-create
installs a pinned checkout of [`vim-sensible`](https://github.com/tpope/vim-sensible/tree/master)
into both the Vim and Neovim native package paths so the same default behavior
applies in either editor.

`kubie` is included because the repo keeps split kubeconfigs such as
`~/.kube/kind-kind-local.yaml`, `~/.kube/limavm-k3s.yaml`, and
`~/.kube/slicer-k3s.yaml`. `kubie lint` is useful when checking those files,
and the repo no longer auto-merges them into `~/.kube/config` by default.

If you deliberately need a repo context copied into `~/.kube/config`, use the
explicit `make merge-default-kubeconfig` target in that cluster directory.

Full Playwright browser E2E is host-oriented. The devcontainer no longer bakes
Chromium runtime libraries, so `check-sso-e2e` should be run from the host
unless you intentionally provision browser dependencies yourself.
