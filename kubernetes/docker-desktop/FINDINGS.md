# Docker Desktop Findings

Repository note:

- `kubernetes/docker-desktop` now keeps findings and reusable experiment
  scripts only
- the staged `tfvars` ladder was intentionally removed after the March 2026
  research cycle

## March 16, 2026

### Summary

Docker Desktop managed Kubernetes is feasible as a fourth local target, but it
has one material difference from `kind`, `lima`, and `slicer`:

- the managed node containers ship with `/etc/containerd/certs.d/_default/hosts.toml`
  pointing every registry lookup at `http://registry-mirror:1273`
- that mirror returns HTTP `500` for local workload registries like
  `host.docker.internal:5002/*`
- stage `900` therefore applies cleanly, but app workloads that use external
  local images stay in `ErrImagePull` until the nodes are patched

### What Worked

- Docker Desktop managed `kind` cluster creation at Kubernetes `v1.35.1`
- Cilium `1.19.1` installation and repeatable workload placement
- `10/10` successful reset-and-migrate loops via
  `scripts/cilium-workload-loop.sh`
- Terraform/OpenTofu stage `900` apply against the shared stack
- Argo CD, Gitea, Dex, Headlamp, Hubble, NGINX Gateway Fabric, cert-manager,
  Prometheus, Loki, policy-reporter, and APIM

### Docker Desktop-Specific Workaround

After cluster creation, patch the managed node containers with explicit
registry-specific `hosts.toml` entries and restart `containerd`:

```bash
./kubernetes/docker-desktop/scripts/patch-managed-kind-registry.sh --restart-workloads
```

That bypasses the broken `_default` mirror path for:

- `host.docker.internal:5002`
- `192.168.65.254:5002`

### Current End State

After the node patch:

- new kubelet pulls from `host.docker.internal:5002/*` succeeded
- stage `900` completed successfully
- an idempotent follow-up stage `900` apply also completed successfully
- `dev`, `uat`, and `apim` converged to `Healthy`
- the remaining tail on the observed run moved to
  `prometheus-kube-state-metrics` probe flapping inside the observability
  stack, not the Docker Desktop platform itself

### Practical Conclusion

If the question is "can Docker Desktop managed Kubernetes run this shared local
platform with Cilium and higher stages?":

- yes, with a post-create node patch for containerd registry overrides
- yes, for in-cluster workloads and platform resources

If the question is "is it a drop-in replacement for `kubernetes/kind` without
special handling?":

- no, not yet
- on the observed March 16, 2026 run, Docker Desktop only published the API
  server port from the managed node containers, so host URLs such as
  `https://grafana.admin.127.0.0.1.sslip.io/` and direct NodePort access on
  macOS were not reachable even though the Gateway, HTTPRoutes, Services, and
  backing pods existed in-cluster
- a follow-up March 17, 2026 `LoadBalancer` check showed the bundled
  `kind-cloud-provider` assigns a Docker-network ingress IP (`172.18.x.x`) and
  runs its proxy inside the Docker network, but still does not publish a host
  listener on macOS

### Managed Tab vs `kind` CLI

On March 17, 2026, a disposable hand-managed `kind` cluster was created on the
same Docker Desktop engine with:

- cluster name `dd-cli-compare`
- API server bind `127.0.0.1:18443`
- explicit `extraPortMappings` entry `127.0.0.1:18080 -> 30080/tcp`

After deploying a trivial `NodePort` service on `30080`, the host check:

```bash
curl http://127.0.0.1:18080/
```

returned the expected payload.

That makes the practical difference clear:

- Docker Desktop as the container runtime is not the problem
- the constraint sits in the Docker Desktop Kubernetes-tab management layer
- hand-managed `kind` on Docker Desktop exposes a more useful operator surface
  because port mappings are declared up front and honored directly by the node
  containers

Recommendation:

- keep `kubernetes/docker-desktop` as a findings-oriented research target, not
  a first-class local platform alongside `kubernetes/kind`
