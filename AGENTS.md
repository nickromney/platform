Use the repo-local `use-platform` skill at `skills/use-platform/SKILL.md` first if your agent supports installable skills. Then run `make` at the root; it is informational and points to focused Makefiles. Choose a subtree with `make -C apps help`, `make -C docker/compose help`, `make -C kubernetes/kind help`, or `make -C kubernetes/lima help`, then read the nearest subtree `README.md`.

## The gate is local. Run it yourself before you push

**GitHub CI does not run on pull requests** (ADR 0011). It runs on `main` and on
`workflow_dispatch` only. Nothing remote will catch your branch for you.

Run this before pushing:

```bash
make lint && make test-ci
```

`make test-ci` stamps `.run/ci-receipt.json` with a fingerprint of the exact
tree it verified. The pre-push hook checks that receipt against the tree you are
pushing: if it matches, the push proceeds in milliseconds; if the tree has
changed since, the push is refused and tells you to re-run. So a stale receipt
costs you one message, not twelve minutes — but you do have to run the gate.

The receipt covers uncommitted and untracked-not-ignored files too, not just
`HEAD`. It has no expiry: it is valid while the tree matches, and worthless the
moment a file changes.

Git hooks come from lefthook (`make hooks` installs them from `lefthook.yml`)
and fire at commit and push, not while you work. What they cover:

- **pre-commit** lints only *staged* files — shellcheck on `*.sh`, yamllint on
  `*.{yaml,yml}`, duplicate keys in `kubernetes/kind/**/*.tfvars`. Nothing
  repo-wide, no tests.
- **pre-push** runs `make lint` (~90s) then verifies the receipt.
  `PLATFORM_LOCAL_CI_FULL=1 git push` runs the whole suite inline instead, but
  git opens the SSH connection before the hook runs, so a ~12-minute hook can
  outlive it and the push dies with "Connection closed by remote host". Running
  `make test-ci` first avoids that race.

Two things the gate does **not** check, so run them yourself when touching Go:

```bash
gofmt -l tools/ apps/
cd <module> && go test -race ./...
```

Both have already caught real bugs here that a full green gate did not.

Also note `make lint`'s shell audit only sees **tracked** files, so `git add`
new scripts before trusting a clean run. New `*.bats` and `go.mod` files are
picked up automatically once tracked — both are discovered with `git ls-files`.

When remote confirmation genuinely matters, dispatch it:

```bash
gh workflow run ci.yml --ref <branch>
```

## Cursor Cloud specific instructions

For cloud agents on the ephemeral Cursor Cloud VM (Ubuntu 24.04, Firecracker guest
kernel). Only non-obvious, durable gotchas are recorded here; standard commands live
in the root `README.md`, `make help`, and the focused subtree Makefiles.

### What runs on this VM, and what does not

- Fully works: the Go apps under `apps/` (`go run`/`go test`, and per-app
  `make -C apps/<name>/app test`), plus the repo dev gate `make lint` and
  `make test-ci`. The startup update script installs the toolchain for these.
- Works: the kind cluster bootstrap, `make -C kubernetes/kind 100 apply
  AUTO_APPROVE=1`, but only with the containerd snapshotter override below.
- Does NOT work here: Cilium (stage 200) and therefore the whole 200->900
  platform. The Firecracker guest kernel (`uname -r` = `6.12.94+`) ships no
  loadable modules (`/lib/modules/<kernel>` is empty) and lacks `ip_set` and
  GENEVE, which Cilium's datapath requires (agent dies with
  `fatal ... error while creating ipset cilium_node_set_v4`). This is a kernel
  capability gap, not a tooling gap: run the full stack on a real host kernel
  (laptop or a dedicated server with host-level everything) or the devcontainer,
  per `kubernetes/kind/README.md`.

### Toolchain and pins

- Go 1.26 is required by every `go.mod` and by CI (`.github/workflows/ci.yml`
  `setup-go: "1.26"`); the update script installs it.
- `shellcheck` must be the pinned `v0.11.0`. Ubuntu's apt build is `0.9.0`, which
  emits hundreds of false `SC2317` findings and fails `make lint`
  (see the note in `.devcontainer/toolchain-versions.sh`).
- Tool versions come from `.devcontainer/toolchain-versions.sh` (the pin source of
  truth), cooldown-governed by `make update-versions` / `make check-version`.
- `node` on this VM is a `/exec-daemon/node` shim whose npm `prefix` resolves to
  `/`, so a plain `npm i -g <pkg>` fails with `EACCES`. Install global npm CLIs
  with `--prefix /usr/local` (that is how `markdownlint-cli2` is installed).

### Container runtime and kind (on-demand; not in the update script)

Docker is a daemon (a service), so it is intentionally not installed/started by the
startup script. Bring it up on demand when you need `compose-smoke` or a kind
cluster (the repo is runtime-agnostic and also accepts podman/nerdctl via
`scripts/lib/compose-cli.sh`; no Docker Desktop needed):

- Install Docker Engine natively on the host. This kernel needs daemon settings
  `storage-driver=fuse-overlayfs`, `features.containerd-snapshotter=false`
  (Docker 29), and `iptables-legacy`.
- To create ANY kind cluster here you MUST
  `export KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER=fuse-overlayfs` before
  `kind`/`make -C kubernetes/kind ... apply`; otherwise the node's containerd
  fails with `overlay ... invalid argument` (nested overlayfs is unsupported).
  Also raise `fs.inotify.max_user_instances` and `kernel.keys.maxkeys` for kubeadm.
- Stages >= 600 additionally require `docker login dhi.io` (Docker Hardened Images)
  credentials.
