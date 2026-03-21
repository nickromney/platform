# Devcontainer

This repo ships a devcontainer for the Linux-friendly workflows in the
repository. It is based on Ubuntu 24.04 and is intended to run the same
`make prereqs` entrypoints as the host, without special-case Make logic.

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

## Recommended Start Path

This is the first-class path for this repo.

1. Start your local Docker daemon.
2. Install the VS Code Dev Containers extension.
3. Open this repository in VS Code.
4. Run `Dev Containers: Open Folder in Container...` from the Command Palette.
   If the folder is already open, `Dev Containers: Reopen in Container` is
   equivalent.
5. Wait for the image build and post-create setup to finish.
6. Verify the toolchain from inside the container:

```bash
make -C apps prereqs
make -C kubernetes/kind prereqs
```

## Terminal-Only Start Path

If you do not want to use VS Code, use the Dev Container CLI:

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

The devcontainer prefers installers over hand-managed binaries:

- Homebrew: general CLI/runtime layer, including `starship`, `yamllint`, and
  `kyverno`.
- `arkade`: Kubernetes-facing tools, including `kubectl`, `kind`, `helm`,
  `cilium`, `hubble`, `k3sup`, `kubie`, `terragrunt`, and `tofu`.

The repo-level `make lint` entrypoint works inside the devcontainer too, and
the image now includes both `yamllint` and `kyverno` for the recursive YAML and
local policy validation passes.

It also seeds shell startup for both `bash` and `zsh` so the container has:

- `EDITOR=nvim` and `VISUAL=nvim`
- `node`, `npm`, `npx`, and `bun` for browser/E2E test flows
- the Linux Chromium runtime libraries that Playwright expects, while the
  Playwright CLI itself stays project-local via `bun x playwright` or
  `npx playwright`
- generated completion scripts for `kubectl`, `kubie`, `kind`, `helm`,
  `cilium`, and `hubble` when those binaries are present
- `starship` prompt init in both shells

It also seeds:

- `~/.config/starship.toml` from
  [`starship.toml`](./starship.toml)
- managed shell includes sourced from `~/.bashrc` and `~/.zshrc`

For editing inside the container, Homebrew installs `neovim`, and post-create
installs a pinned checkout of [`vim-sensible`](https://github.com/tpope/vim-sensible/tree/master)
into both the Vim and Neovim native package paths so the same default behavior
applies in either editor.

`kubie` is included because the repo keeps split kubeconfigs such as
`~/.kube/kind-kind-local.yaml`, `~/.kube/limavm-k3s.yaml`, and
`~/.kube/slicer-k3s.yaml`. `kubie lint` is useful when checking those files,
and the repo no longer auto-merges them into `~/.kube/config` by default.

If you deliberately need a repo context copied into `~/.kube/config`, use the
explicit `make merge-default-kubeconfig` target in that cluster directory.
