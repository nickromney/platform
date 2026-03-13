# lima

Local Kubernetes fallback cluster on Lima VMs.

`kubernetes/lima` keeps the same cumulative stage ladder as
[`../kind`](../kind/README.md), but stage `100` boots k3s on Lima and stages
`200+` apply the shared [`../../terraform/kubernetes`](../../terraform/kubernetes)
stack against that existing kubeconfig-backed cluster.

This path is intentionally separate from the SD-WAN lab in
[`../../sd-wan/lima`](../../sd-wan/lima/README.md).
The current Kind stage ladder and `terraform/kubernetes` inputs are the
canonical shape; the earlier Lima path was used only as bootstrap reference.

## Quick start

From the project root:

```bash
make -C kubernetes/lima prereqs
make -C kubernetes/lima 100 apply
make -C kubernetes/lima 900 plan
make -C kubernetes/lima 900 apply AUTO_APPROVE=1
make -C kubernetes/lima show-urls
```

Useful follow-ups:

```bash
make -C kubernetes/lima check-health
make -C kubernetes/lima check-sso-e2e
make -C kubernetes/lima status
make -C kubernetes/lima reset AUTO_APPROVE=1
```

## Operational truths

- The stage model is cumulative. `make -C kubernetes/lima 900 apply` means
  "bring the Lima-backed cluster to the stage-900 shape", not "run only the
  last step".
- Stage `100` is the bootstrap boundary. It creates or starts the Lima VM(s),
  installs k3s with `k3sup`, and writes `~/.kube/limavm-k3s.yaml`.
- Stages `200+` reuse the shared Terraform platform root. The Lima target
  profile disables kind-only plumbing such as kind provisioning, Docker socket
  mounts, the in-cluster actions runner, and Cilium WireGuard.
- Hardened platform images stay on their upstream refs (`dhi.io`, `quay.io`,
  `ghcr.io`, `docker.io`, and so on). When the host cache at
  `host.lima.internal:5002` is available, Lima configures containerd to try it
  first as a mirror and then fall back upstream.
- Stage `700+` workload images are different: they are built locally on the
  host and pushed to the Lima cache at `127.0.0.1:5002`, which the cluster then
  pulls as `host.lima.internal:5002`.
- On a 16 GB host, stop the kind cluster before starting Lima so Docker Desktop
  and Lima are not competing for RAM:

  ```bash
  make -C kubernetes/kind stop-kind
  ```

## Stage ladder

| Stage | Intent |
| --- | --- |
| `100` | Bootstrap k3s on Lima |
| `200` | Install Cilium |
| `300` | Add Hubble |
| `400` | Add Argo CD |
| `500` | Add Gitea |
| `600` | Add policies |
| `700` | Deploy app workloads from local images |
| `800` | Add HTTPS routes and observability |
| `900` | Add SSO |

## Layout

- `Makefile` is the standalone Lima operator surface.
- `preload-images.txt` is the Lima image-list source of truth used by version
  checks and optional platform-image cache sync.
- `config/lima-k3s-node.yaml` defines the Lima VM template.
- `targets/lima.tfvars` is the Lima-specific Terraform target profile.
- `stages/` contains the cumulative stage ladder used against the shared
  Terraform stack.
- `scripts/` contains the Lima bootstrap, proxy, cache, and local image-build
  helpers.
- `tests/` contains bats coverage for the Lima-only scripts.
