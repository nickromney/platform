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

If you intend to expose any Kubernetes target off-host, read the shared
[OWASP analysis and public-demo checklist](../../docs/OWASP-analysis.md)
before you apply a public-facing profile.

## Quick start

From the project root:

```bash
make -C kubernetes/lima prereqs
make -C kubernetes/lima 100 apply
make -C kubernetes/lima 900 plan
make -C kubernetes/lima 900 apply AUTO_APPROVE=1
make -C kubernetes/lima 900 check-health
make -C kubernetes/lima 900 show-urls
```

Useful follow-ups:

```bash
make -C kubernetes/lima 900 check-health DRY_RUN=1
make -C kubernetes/lima check-sso-e2e
make -C kubernetes/lima exercise-k3s-oidc-recovery OIDC_RECOVERY_FORMAT=json
make -C kubernetes/lima status
make -C kubernetes/lima reset AUTO_APPROVE=1
```

The stage-first positional Make syntax remains supported, for example
`make -C kubernetes/lima 100 apply`. Read-only Make targets now pass
`--execute` to the underlying scripts explicitly; set `DRY_RUN=1` to preview
them with `--dry-run`.

Helper toggles are explicit now:

- `LIMA_HOST_GATEWAY_PROXY_MODE=auto|on|off` controls whether the target
  manages the host-gateway proxy helpers used by localhost-backed flows such as
  SSO E2E checks and stable UI URLs. `auto` preserves the current behavior.
- `PLATFORM_LOCAL_IMAGE_CACHE_MODE=auto|on|off` controls whether the target
  manages and syncs the host registry cache. `auto` preserves the current
  behavior and turns it on from stage `700`.
- `PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=auto|on|off` controls whether the
  target builds and pushes the local workload images. `auto` preserves the
  current behavior and turns it on from stage `700`.

If a helper mode is `off`, the target stops managing that dependency. Later
stages can still work, but only if an equivalent service is already present.
For example, stage `700+` still expects workload images to exist at
`host.lima.internal:5002`; with cache management disabled, the Makefile now
fails fast unless a compatible registry is already reachable.

`make -C kubernetes/lima exercise-k3s-oidc-recovery` is the Lima-specific
operator drill for the stage-900 k3s OIDC restart path. It first converges the
guest OIDC config with `configure-k3s-apiserver-oidc`, then forces a `k3s`
restart, proves the API outage was observed, and verifies that API readiness,
Gateway programming, and in-VM OIDC issuer reachability all recover. Set
`OIDC_RECOVERY_FORMAT=json` for a single machine-readable result object.

The Lima target profile now sets `gitea_local_access_mode = "port-forward"`.
That keeps the shared Terraform Gitea automation working without assuming a
separate localhost proxy is already exposing `30090`/`30022`; the narrow
Gitea access for repo/admin bootstrap is established on demand with
`kubectl port-forward`.

If you need those tunnels manually while debugging from the host, run:

```bash
kubectl -n gitea port-forward svc/gitea-http 3000:3000
kubectl -n gitea port-forward svc/gitea-ssh 2222:22
```

Then use:

- `http://127.0.0.1:3000/` for the UI
- `ssh://git@127.0.0.1:2222/<owner>/<repo>.git` for SSH clone URLs

## Operational truths

- The stage model is cumulative. `make -C kubernetes/lima 900 apply` means
  "bring the Lima-backed cluster to the stage-900 shape", not "run only the
  last step".
- Stage `100` is the bootstrap boundary. It creates or starts the Lima VM(s),
  installs k3s with `k3sup`, and writes `~/.kube/limavm-k3s.yaml`.
- The repo-owned kubeconfig stays split by default. Use `kubie` across
  `~/.kube/*.yaml`, and only run `make -C kubernetes/lima merge-default-kubeconfig`
  if you intentionally want `limavm-k3s` copied into `~/.kube/config`.
- Stage `900` now also configures the Lima k3s apiserver to trust OIDC-issued
  Headlamp tokens, so a fresh `900 apply` leaves Headlamp login-ready without a
  separate repair step.
- Stage `900` is the confidence path when you drive it through `make`. A
  successful `make -C kubernetes/lima 900 apply` now also runs `check-health`
  before returning success. Keep `make -C kubernetes/lima check-sso-e2e` as an
  explicit post-apply browser smoke check. Raw Terragrunt/OpenTofu applies
  remain apply-only.
- Stages `200+` reuse the shared Terraform platform root. The Lima target
  profile disables kind-only plumbing such as kind provisioning, Docker socket
  mounts, the in-cluster actions runner, and Cilium WireGuard.
- The Lima target profile also switches host-side Gitea automation to
  `gitea_local_access_mode = "port-forward"` so it stays decoupled from the
  broader host-gateway proxy surface.
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
| `100` | Cluster available |
| `200` | Install Cilium |
| `300` | Add Hubble |
| `400` | Add Argo CD |
| `500` | Add Gitea |
| `600` | Add policies |
| `700` | Add app repos |
| `800` | Add observability |
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

For older Lima clusters created before this wiring was moved into `900 apply`,
rerun `make -C kubernetes/lima 900 apply AUTO_APPROVE=1` or run
`make -C kubernetes/lima configure-k3s-apiserver-oidc` once before relying on
Headlamp. `make -C kubernetes/lima check-sso-e2e` remains an explicit
post-apply validation step and no longer patches the VM first.
