# docker-desktop

Research notes and experiment scripts for Docker Desktop's managed Kubernetes
tab.

This directory is intentionally not a first-class staged deployment target.
The staged `tfvars` ladder was removed after the March 2026 experiments. What
remains here is the useful part: findings, repeatable scripts, and a small
amount of reference data for debugging Docker Desktop-specific edge cases.

For the supported local path with predictable host port mappings and better
cluster control, use [`../kind`](../kind/README.md).

## What Was Proved

On March 16-17, 2026, Docker Desktop managed Kubernetes was tested in managed
`kind` mode with:

- Kubernetes `v1.35.1`
- `2` nodes
- context `docker-desktop`
- Cilium `1.19.1`

The useful results were:

- Docker Desktop can run a managed `kind` cluster and tolerate a Cilium
  migration instead of staying on the bundled `kindnet` CNI.
- The Cilium cutover can be repeated from a reset cluster. A `10/10` loop run
  succeeded with real workload placement on both nodes.
- The shared platform stack can be applied far enough to populate the Docker
  Desktop Kubernetes tab with the expected namespaces, apps, and routes.
- Docker Desktop's managed nodes need a post-create containerd registry patch
  before kubelet can pull local workload images from
  `host.docker.internal:5002`.
- The managed Kubernetes tab still does not expose the platform gateway or
  workload `NodePort` services back to the macOS host in the same way a
  hand-managed `kind` cluster does.

The longer write-up is in [`FINDINGS.md`](FINDINGS.md).

## Scripts

### `scripts/cilium-workload-loop.sh`

Repeatable reset-and-migrate harness for the Docker Desktop managed cluster.

What it does:

- calls the Docker Desktop backend socket to reset or start the managed cluster
- waits for the `docker-desktop` kubeconfig context to become usable
- installs Cilium in migration mode
- labels both nodes with `CiliumNodeConfig`
- forces the Cilium agents to rewrite `/etc/cni/net.d`
- recycles CoreDNS
- deploys a smoke `DaemonSet` and verifies one Cilium-backed pod lands on each
  node

Useful environment overrides:

- `KUBECONFIG_CONTEXT` default `docker-desktop`
- `DESIRED_VERSION` default `1.35.1`
- `DESIRED_NODE_COUNT` default `2`
- `CILIUM_VERSION` default `1.19.1`
- `MAX_LOOPS` default `10`
- `RUN_ID` to pin the output directory name
- `RUN_ROOT` to change where `.run/` artifacts are written

Typical use:

```bash
MAX_LOOPS=10 RUN_ID=smoke-check ./kubernetes/docker-desktop/scripts/cilium-workload-loop.sh
```

Artifacts are written under `kubernetes/docker-desktop/.run/<run-id>/`.

### `scripts/patch-managed-kind-registry.sh`

Patch Docker Desktop managed node containers so `containerd` can pull local
images directly instead of forcing them through Docker Desktop's registry-mirror
fallback.

What it does:

- discovers managed node containers matching `^desktop-`
- writes per-registry `hosts.toml` overrides under
  `/etc/containerd/certs.d/<registry>/`
- restarts `containerd` inside each node container
- optionally restarts app deployments in `dev`, `uat`, and `apim`

Useful options:

- `--context NAME`
- `--node-pattern REGEX`
- `--registry HOST:PORT`
- `--restart-workloads`

Typical use:

```bash
./kubernetes/docker-desktop/scripts/patch-managed-kind-registry.sh --restart-workloads
```

## Reference Files

- `targets/docker-desktop.tfvars` is kept as a reference capture of the
  Docker Desktop-specific existing-cluster settings used during the experiment.
- `preload-images.txt` is the image list snapshot that was used during the
  research runs.

## Practical Position

Treat this folder as a research target for:

- Docker Desktop-specific Cilium migration experiments
- registry-mirror debugging
- managed-cluster regression checks
- edge-case handling that may later inform the supported targets

Do not treat it as equivalent to [`../kind`](../kind/README.md). The key gap is
still host reachability and operator control: on this machine, the Docker
Desktop Kubernetes tab populated successfully, but host-facing workload access
still lagged behind the hand-managed `kind` path.
