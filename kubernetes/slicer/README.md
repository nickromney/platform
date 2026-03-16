# slicer

Working, with caveats.

`kubernetes/slicer` now reaches the full shared stage ladder again on the
current on-device `slicer-mac` image, including the `cilium` profile through
stage `900`.

As of March 14, 2026, the validated shape is:

- host config from
  [`~/slicer-mac/slicer-mac.yaml`](/Users/nickromney/slicer-mac/slicer-mac.yaml)
- `slicer-1` in the `slicer` group
- `8GiB` RAM
- `25G` root disk
- localhost HTTPS entrypoint on `:8443`

This target still carries useful operational caveats:

- Older images and smaller disks were not stable. Earlier `15G` roots hit node
  disk pressure around stage `800`, and older image/kernel combinations showed
  ext4 plus containerd corruption under Cilium/Hubble load.
- The lighter `SLICER_NETWORK_PROFILE=default` path is still valuable when you
  want a teaching cluster without Cilium/Hubble/service-mesh behavior.
- Slicer host forwards are unprivileged on macOS, so the gateway does not bind
  host port `443`; use `https://*.127.0.0.1.sslip.io:8443/...` in this target.

This target follows the current Kind/Lima plus shared Terraform shape. The old
`publiccloudexperiments/platforms/slicervm` tree is reference material only for
bootstrap/runtime details.

## Reference commands

These commands describe the current operator surface. The `cilium` profile is
still experimental; `default` is the lighter teaching-cluster profile that
keeps k3s' built-in networking and skips Cilium/Hubble/policies.

From the project root:

```bash
export SLICER_VM_GROUP=slicer
make -C kubernetes/slicer prereqs
make -C kubernetes/slicer 100 apply
make -C kubernetes/slicer 500 apply SLICER_NETWORK_PROFILE=default
make -C kubernetes/slicer 900 plan
make -C kubernetes/slicer 900 apply AUTO_APPROVE=1
make -C kubernetes/slicer show-urls
```

For the current Slicer-backed HTTPS routes, append `:8443`, for example:

- `https://gitea.admin.127.0.0.1.sslip.io:8443/`
- `https://grafana.admin.127.0.0.1.sslip.io:8443/`
- `https://dex.127.0.0.1.sslip.io:8443/dex`

Useful follow-ups while debugging:

```bash
make -C kubernetes/slicer check-health
make -C kubernetes/slicer check-sso-e2e
make -C kubernetes/slicer status
make -C kubernetes/slicer reset AUTO_APPROVE=1
```

Helper toggles are explicit now:

- `SLICER_HOST_FORWARDS_MODE=auto|on|off` controls whether the target manages
  the localhost forwarder used for stable operator-facing URLs and checks.
  `auto` preserves the current behavior and turns it on from stage `500`.
- `PLATFORM_LOCAL_IMAGE_CACHE_MODE=auto|on|off` controls whether the target
  manages and syncs the host registry cache. `auto` preserves the current
  behavior and turns it on from stage `700`.
- `PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=auto|on|off` controls whether the
  target builds and pushes the local workload images. `auto` preserves the
  current behavior and turns it on from stage `700`.

If a helper mode is `off`, the target stops managing that dependency. Later
stages can still work, but only if an equivalent service is already present.
For example, stage `700+` still expects workload images to exist at
`192.168.64.1:5002`; with cache management disabled, the Makefile now fails
fast unless a compatible registry is already reachable.
Shared Terraform Gitea automation is now decoupled from the broad Slicer host
forward bundle. The Slicer target profile sets
`gitea_local_access_mode = "port-forward"`, so repo/admin bootstrap steps use
temporary `kubectl port-forward` tunnels instead of assuming
`127.0.0.1:30090`/`127.0.0.1:30022` already exist. `SLICER_HOST_FORWARDS_MODE`
is still useful for stable localhost UI surfaces and health checks, but it is
no longer the hidden prerequisite for stage `500+` applies.

## Operational truths

- The stage model is cumulative. `make -C kubernetes/slicer 900 apply` means
  "bring the Slicer-backed cluster to the stage-900 shape", not "run only the
  last step".
- The current working shape depends on VM sizing. The validated full-stack run
  used the current on-device image plus a `25G` root disk; smaller roots hit
  node disk pressure at later stages.
- Stage `100` is the bootstrap boundary. It requires the on-device
  `slicer-mac` daemon at
  [`~/slicer-mac/slicer-mac.yaml`](/Users/nickromney/slicer-mac/slicer-mac.yaml),
  ensures the selected VM exists in the selected host group, installs k3s with
  `k3sup --local` inside the VM, and writes `~/.kube/slicer-k3s.yaml`.
- The bootstrap keeps the Slicer-specific host-health guards that still pull
  their weight on current images: swap creation and ext4 error checks.
- Stages `200+` reuse the shared Terraform platform root. The Slicer target
  profile disables kind-only plumbing such as kind provisioning, Docker socket
  mounts, and the in-cluster actions runner.
- `SLICER_VM_NAME` now defaults to `$(SLICER_VM_GROUP)-1`. For the on-device
  Slicer group, `export SLICER_VM_GROUP=slicer` gives you `slicer-1` by
  default; override `SLICER_VM_NAME` explicitly if you want a different VM.
- The Slicer target profile also switches host-side Gitea automation to
  `gitea_local_access_mode = "port-forward"`. That keeps the shared Terraform
  path working without assuming the full localhost forward bundle is present.
- `SLICER_NETWORK_PROFILE=default` keeps the k3s default CNI in place. In that
  profile, stages `200`, `300`, and `600` are intentional no-op placeholders so
  the stage numbers still line up with Kind/Lima and the full Cilium path.
- Switching between `SLICER_NETWORK_PROFILE=cilium` and
  `SLICER_NETWORK_PROFILE=default` is not an in-place upgrade. Reset the VM
  first; bootstrap refuses to reuse an existing k3s install if the network
  profile changed.
- Hardened platform images stay on upstream refs. When a local cache is
  available at `192.168.64.1:5002`, Slicer configures containerd to try it
  first as a mirror and then fall back upstream.
- Stage `700+` workload images are different: they are built locally on the
  host and pushed to `127.0.0.1:5002`, which the cluster then pulls as
  `192.168.64.1:5002`.
- Slicer needs an explicit host forwarder so localhost URLs line up with Kind
  and Lima. The target manages that via `make ensure-host-forwards`, mapping:
  `30080`, `31235`, `30090`, `30022`, `3301`, `3302`, and `8443`.
- Because that forwarder is unprivileged on macOS, the TLS gateway URL is
  `https://...:8443`, not bare `443`.
- The host-port preflight checks the Slicer-local URL surface before stage
  `100`, so Kind/Lima/Slicer do not silently overlap on the same host ports.

## Stage ladder

| Stage | Intent |
| --- | --- |
| `100` | Bootstrap k3s on Slicer |
| `200` | Install Cilium, or no-op placeholder for `SLICER_NETWORK_PROFILE=default` |
| `300` | Add Hubble, or no-op placeholder for `SLICER_NETWORK_PROFILE=default` |
| `400` | Add Argo CD |
| `500` | Add Gitea |
| `600` | Add policies, or no-op placeholder for `SLICER_NETWORK_PROFILE=default` |
| `700` | Deploy app workloads from local images |
| `800` | Add HTTPS routes and observability |
| `900` | Add SSO |

## Layout

- `Makefile` is the standalone Slicer operator surface.
- `preload-images.txt` is the Slicer image-list source of truth used by version
  checks and optional platform-image cache sync.
- `targets/slicer.tfvars` is the Slicer-specific Terraform target profile.
- `stages/` contains the cumulative Cilium/Hubble ladder used against the
  shared Terraform stack.
- `stages/default-cni/` contains the fallback ladder that keeps the default
  k3s CNI and omits Cilium/Hubble/policies.
- `scripts/` contains the Slicer bootstrap, daemon, host-forward, cache, and
  local image-build helpers.
- `tests/` contains bats coverage for the Slicer-only scripts.
