Use the repo-local `use-platform` skill at `skills/use-platform/SKILL.md` first if your agent supports installable skills. Then run `make` at the root; it is informational and points to focused Makefiles. Choose a subtree with `make -C apps help`, `make -C docker/compose help`, `make -C kubernetes/kind help`, or `make -C kubernetes/lima help`, then read the nearest subtree `README.md`.

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
