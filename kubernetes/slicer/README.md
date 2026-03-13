# slicer

Experimental. Not yet working.

`kubernetes/slicer` is checked in as active investigation and reference
material, not as a supported local-cluster path. Do not rely on it yet.

As of March 13, 2026, live runs are not reliable enough to recommend:

- `sbox-1` could reach `K3s + Cilium`, but later widen into reboots plus
  ext4 and containerd corruption under heavier workload.
- `slicer-1` rebooted and logged ext4 corruption after `K3s + Cilium` alone.

Use [`../kind`](../kind/README.md) or [`../lima`](../lima/README.md) if you
want a working local path today.

The target shape is still here so the ported Makefile, scripts, and target
profile are not lost, and so we have a concrete surface to resume once the
underlying runtime is stable.

This target follows the current Kind/Lima plus shared Terraform shape. The old
`publiccloudexperiments/platforms/slicervm` tree is reference material only for
bootstrap/runtime details.

## Reference commands

These commands describe the intended operator surface. They are not a promise
that the target currently converges cleanly.

From the project root:

```bash
make -C kubernetes/slicer prereqs
make -C kubernetes/slicer 100 apply
make -C kubernetes/slicer 900 plan
make -C kubernetes/slicer 900 apply AUTO_APPROVE=1
make -C kubernetes/slicer show-urls
```

Useful follow-ups while debugging:

```bash
make -C kubernetes/slicer check-health
make -C kubernetes/slicer check-sso-e2e
make -C kubernetes/slicer status
make -C kubernetes/slicer reset AUTO_APPROVE=1
```

## Operational truths

- The stage model is cumulative. `make -C kubernetes/slicer 900 apply` means
  "bring the Slicer-backed cluster to the stage-900 shape", not "run only the
  last step".
- The current blocker is runtime stability, not target structure. The repo now
  has the right Slicer-shaped Makefile and stage ladder, but the guest can
  still reboot and return with filesystem damage.
- Stage `100` is the bootstrap boundary. It reuses the running `slicer-mac`
  daemon when available, otherwise falls back to a repo-managed daemon config,
  ensures `sbox-1` exists, installs k3s with `k3sup --local` inside the VM,
  and writes `~/.kube/slicer-k3s.yaml`.
- The bootstrap keeps the Slicer-specific stability guards from the older
  prototype: swap creation, ext4 error checks, and a default BPF-JIT disable
  toggle for Cilium stability.
- Stages `200+` reuse the shared Terraform platform root. The Slicer target
  profile disables kind-only plumbing such as kind provisioning, Docker socket
  mounts, and the in-cluster actions runner.
- Hardened platform images stay on upstream refs. When a local cache is
  available at `192.168.64.1:5002`, Slicer configures containerd to try it
  first as a mirror and then fall back upstream.
- Stage `700+` workload images are different: they are built locally on the
  host and pushed to `127.0.0.1:5002`, which the cluster then pulls as
  `192.168.64.1:5002`.
- Slicer needs an explicit host forwarder so localhost URLs line up with Kind
  and Lima. The target manages that via `make ensure-host-forwards`, mapping:
  `30080`, `31235`, `30090`, `30022`, `3301`, `3302`, and `8443`.
- The host-port preflight checks the Slicer-local URL surface before stage
  `100`, so Kind/Lima/Slicer do not silently overlap on the same host ports.

## Stage ladder

| Stage | Intent |
| --- | --- |
| `100` | Bootstrap k3s on Slicer |
| `200` | Install Cilium |
| `300` | Add Hubble |
| `400` | Add Argo CD |
| `500` | Add Gitea |
| `600` | Add policies |
| `700` | Deploy app workloads from local images |
| `800` | Add HTTPS routes and observability |
| `900` | Add SSO |

## Layout

- `Makefile` is the standalone Slicer operator surface.
- `preload-images.txt` is the Slicer image-list source of truth used by version
  checks and optional platform-image cache sync.
- `targets/slicer.tfvars` is the Slicer-specific Terraform target profile.
- `stages/` contains the cumulative stage ladder used against the shared
  Terraform stack.
- `config/slicer-mac.yaml` is the fallback repo-managed Slicer daemon config.
- `scripts/` contains the Slicer bootstrap, daemon, host-forward, cache, and
  local image-build helpers.
- `tests/` contains bats coverage for the Slicer-only scripts.
