# platform (local platform demo)

## Intent

This stack is a reproducible, local "platform-in-a-box" demo that shows:

- **Kubernetes (kind)** as the local cluster
- **Cilium + Hubble** for CNI and L7 visibility
- **Gitea** as both:
  - the Git server backing GitOps
  - the CI system (Gitea Actions)
  - the container image registry (OCI)
- **Argo CD** using the **app-of-apps** GitOps pattern
- **NGINX Gateway Fabric** (Gateway API) for ingress
- **TLS everywhere** via **cert-manager** + a locally bootstrapped **mkcert CA**
- **Instrumentation/Monitoring** with **SigNoz** (local, open-source "Datadog-like" observability)

## GitOps Chart Sources

The chart source model is now intentionally split:

- Gitea itself is still bootstrapped from `https://dl.gitea.io/charts/`.
- Other chart-based Argo apps are vendored into the Gitea-backed `platform/policies` Git repo under `apps/vendor/charts/*`.
- That lets `argocd-repo-server` render almost everything from in-cluster Gitea Git and keeps the remaining public Helm egress exception down to `dl.gitea.io:443`.

This is a deliberate minimal-bootstrap-exception design, not reliance on local Docker Desktop registry caching for Helm charts.

## Security Verification

The main runtime verifier for this stack is [`../scripts/check-security.sh`](../scripts/check-security.sh).

For the platform gateway, it now does two different kinds of proof:

- black-box checks from outside the cluster:
  - TLS 1.3 succeeds
  - TLS 1.2 compatibility is available on the host-facing gateway path
  - HTTP/2 negotiates
  - HSTS and `X-Content-Type-Options: nosniff` are present on the wire
- white-box checks inside the cluster:
  - the NGINX Gateway Fabric controller is started with `--snippets`
  - the controller RBAC includes `SnippetsPolicy` and `SnippetsFilter`
  - the live rendered NGINX config tree contains every active directive declared in [`../apps/platform-gateway/tls-hardening.yaml`](../apps/platform-gateway/tls-hardening.yaml)

That verifier is intentionally a misconfiguration guardrail, not an admission control. The owner of the repo can still make an intentional change; the point is to catch accidental drift where the manifest exists but the running gateway is not enforcing it.

The broader health check at [`../scripts/check-cluster-health.sh`](../scripts/check-cluster-health.sh) now follows the same model for user-facing admin services:

- direct bootstrap or operator paths where they exist, such as Argo CD on `http://127.0.0.1:30080`, Hubble UI on `http://127.0.0.1:31235`, and the Gitea API NodePort on `http://127.0.0.1:30090`
- gateway + SSO paths for the admin experience, such as `https://argocd.admin.127.0.0.1.sslip.io`, `https://gitea.admin.127.0.0.1.sslip.io`, `https://hubble.admin.127.0.0.1.sslip.io`, `https://grafana.admin.127.0.0.1.sslip.io`, `https://headlamp.admin.127.0.0.1.sslip.io`, and `https://kyverno.admin.127.0.0.1.sslip.io`

## Existing Cluster Mode

The same Terraform root can now run without provisioning Kind by setting `provision_kind_cluster = false`.

- Single stack path: `terraform/kubernetes`
- Default teaching path: [`../../../kubernetes/kind`](../../../kubernetes/kind/README.md), which provisions a Docker-backed kind cluster on macOS or Linux
- Existing-cluster wrappers in this repo:
  - [`../../../kubernetes/lima`](../../../kubernetes/lima/Makefile)
  - [`../../../kubernetes/slicer`](../../../kubernetes/slicer/README.md)

Example for an already-existing cluster:

```bash
cd terraform/kubernetes
terragrunt plan \
  -var 'provision_kind_cluster=false' \
  -var 'kubeconfig_path=~/.kube/config' \
  -var 'kubeconfig_context=my-context'
```

## Architecture Views

These documents are the current reasoning aids for the stack:

- [`apps-c4.md`](./apps-c4.md) gives a mixed Mermaid architecture view of how `sentiment` and `subnetcalc` hang together, combining native C4, UML state diagrams, and sequence diagrams with policy control points on each hop.
- [`../cluster-policies/COMPOSITION.md`](../cluster-policies/COMPOSITION.md) shows the rendered policy composition from the active Kustomize trees.
- [`../cluster-policies/AUDIT.md`](../cluster-policies/AUDIT.md) captures the current policy audit and best-practice gaps.
- [`../../../kubernetes/kind/docs/sample-apps.md`](../../../kubernetes/kind/docs/sample-apps.md) remains the shorter operator-facing walkthrough for the sample apps.

The Cilium model described by those docs is now explicitly layered:

- clusterwide guardrails in [`../cluster-policies/cilium/shared/`](../cluster-policies/cilium/shared/)
- reusable project bundles in [`../cluster-policies/cilium/projects/`](../cluster-policies/cilium/projects/)
- namespace overlays plus namespace-local overrides in [`../cluster-policies/cilium/dev/`](../cluster-policies/cilium/dev/), [`../cluster-policies/cilium/uat/`](../cluster-policies/cilium/uat/), and [`../cluster-policies/cilium/sit/`](../cluster-policies/cilium/sit/)

Namespace intent is now carried by domain-scoped labels rather than generic keys:

- `platform.publiccloudexperiments.net/namespace-role=application|shared|platform`
- `platform.publiccloudexperiments.net/environment=dev|uat|sit`
- `platform.publiccloudexperiments.net/sensitivity=private|confidential|restricted` where needed

The sensitivity vocabulary follows the four-level model described in [SISA Infosec's data classification overview](https://www.sisainfosec.com/blogs/data-classification-levels/):

- `public`
- `private`
- `confidential`
- `restricted`

Current namespace intent in this repo uses:

- `application` for `dev`, `uat`, and the intentionally empty `sit` namespace used to prove namespace-level inheritance before workloads are deployed there
- `shared` for serving-path and runtime shared-service namespaces such as `apim`, `sso`, `observability`, `platform-gateway`, and `gateway-routes`
- `platform` for operator, control, and delivery namespaces such as `argocd`, `cert-manager`, `kyverno`, `nginx-gateway`, `gitea`, `gitea-runner`, `headlamp`, and `policy-reporter`

Core Kubernetes namespaces such as `kube-system`, `kube-public`, and `kube-node-lease` remain intentionally unlabeled and out of this local taxonomy.

## Recommended Stages (Minimal Surface Area)

This stack intentionally keeps the "stage" interface small:

- `100` create the kind cluster (no addons)
- `200` install Cilium (baseline CNI)
- `300` enable Hubble UI
- `900` full stack + SSO (opinionated learning environment)

Typical flow:

```bash
cd kubernetes/kind
make kind apply 100 AUTO_APPROVE=1
make kind apply 200 AUTO_APPROVE=1
make kind apply 300 AUTO_APPROVE=1
make kind apply 900 AUTO_APPROVE=1
```

## Instrumentation / Monitoring

### What emits telemetry

- **Platform metrics/logs/traces** are collected via OpenTelemetry.
- **NGINX Gateway Fabric tracing** is enabled so edge requests produce spans (useful for "did the request reach the cluster" debugging).

### SigNoz trace storage (important for debugging)

SigNoz stores spans in ClickHouse using the **v3 trace schema** (e.g. `signoz_traces.signoz_index_v3`).
If you query older tables like `signoz_traces.distributed_signoz_spans` you may see `0` even when traces are present.

### Service Map / dependency graph

The Service Map depends on **service-to-service relationships** (edges). A single "edge" service (only NGINX spans) will typically not produce a map.

In this stack the dependency graph table (`signoz_traces.dependency_graph_minutes_v2`) is populated via a ClickHouse materialized view over `signoz_traces.signoz_index_v3` that looks for **parent/child spans across different `service.name` values**.

Practically:

- If you only have `service.name = ngf:platform-gateway:platform-gateway`, **Service Map can be empty**.
- Once you have traces that include **multiple services in the same trace** (with context propagation), the dependency graph tables will start to fill and the Service Map should render.

### OpenTelemetry service graph connector (optional)

OpenTelemetry also has a **`servicegraph` connector** which derives service-graph *metrics* (e.g. `traces_service_graph_request_total`) from traces.
If/when we enable it in the collector path, it provides another way to drive service dependency views.

## Next Steps (Registry + Runner + App Repos)

These are the next setup steps for local builds/pulls and for onboarding application repos beyond the platform stack.

### 1) Gitea registry + Kind node trust (required for image pulls)

This stack now writes containerd `hosts.toml` for:
- `docker.io`
- `gitea_registry_host` (default `localhost:30090`)

It also mounts `/etc/containerd/certs.d` into Kind nodes so containerd can pull from the registry.
**Important:** Changing Kind mounts requires recreating the Kind cluster.

Suggested values:
- `gitea_registry_host = "localhost:30090"`
- `gitea_registry_scheme = "http"`
- `enable_docker_socket_mount = true`
- `docker_socket_path = "/var/run/docker.sock"`

Apply notes:
- Any change to Kind mounts will recreate the cluster on the next `make apply`.

### 2) In-cluster Gitea Actions runner (optional, for local builds)

Enable the runner via:
- `enable_actions_runner = true`

The runner uses the host Docker socket and registers itself against the in-cluster Gitea.
This gives you an in‑cluster CI path that can build/push images to the Gitea registry.

### 3) Registry pull secrets for namespaces

If you want workloads to pull images from the local Gitea registry, add namespaces here:
- `registry_secret_namespaces = ["<your-namespace>"]`

This creates a `gitea-registry-creds` secret in each namespace.
You still need to reference the secret from workloads/service accounts:
- `imagePullSecrets: [{ name: gitea-registry-creds }]`

### 4) Flexible app repo onboarding (by design)

We want this to be flexible across teammates and setups:

Option A: **External repo (GitHub, etc.)**
- Create an Argo CD Application that points directly to the external repo.
- Add repo credentials in Argo CD (SSH key or HTTPS token).

Option B: **Mirror into local Gitea**
- Clone the repo locally (or from GitHub) and push into Gitea.
- Point Argo CD at the in-cluster Gitea repo.

We can implement a generic "seed repo" script later that supports:
- `SOURCE=local path` or `SOURCE=git URL`
- `DEST=gitea repo`
- optional filters (subdir, overlays, kustomize/helm)
This keeps onboarding flexible for both local and hosted sources.

### 5) Hybrid app image strategy (external baseline + Gitea-on-change)

This repo now supports a hybrid mode:

- **External baseline images** are built outside the cluster (local scripts or your preferred CI)
- **Gitea images win on app code changes** because app-repo workflows stamp workload manifests to commit-tagged Gitea images

Enable external baseline refs in your stage tfvars:

```hcl
prefer_external_workload_images = true
external_workload_image_refs = {
  sentiment-api                          = "ghcr.io/<owner>/sentiment-api:main"
  sentiment-auth-ui                      = "ghcr.io/<owner>/sentiment-auth-ui:main"
  subnetcalc-api-fastapi-container-app   = "ghcr.io/<owner>/subnetcalc-api-fastapi-container-app:main"
  subnetcalc-apim-simulator              = "ghcr.io/<owner>/subnetcalc-apim-simulator:main"
  subnetcalc-frontend-react              = "ghcr.io/<owner>/subnetcalc-frontend-react:main"
  subnetcalc-frontend-typescript-vite    = "ghcr.io/<owner>/subnetcalc-frontend-typescript-vite:main"
}
```

## Kyverno Policies

Kyverno is deployed via ArgoCD and enforces cluster-wide policies. Policies are stored in `cluster-policies/kyverno/` using a `shared/` and `uat/` hierarchy.

### Topology Spread for subnetcalc frontend

The active topology-spread rule is now owned directly by the `subnetcalc-frontend` workload manifest rather than a Kyverno mutation policy:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    nodeAffinityPolicy: Honor
    nodeTaintsPolicy: Honor
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: subnetcalc-frontend
        app.kubernetes.io/component: frontend
```

**How it works:**

1. The `subnetcalc-frontend` Deployment declares the spread constraint directly in its pod template.
2. `maxSkew: 1` keeps the frontend replicas evenly distributed across nodes.
3. `topologyKey: kubernetes.io/hostname` spreads across worker nodes.
4. `whenUnsatisfiable: DoNotSchedule` makes this a hard scheduling rule instead of a best-effort preference.
5. `nodeAffinityPolicy: Honor` and `nodeTaintsPolicy: Honor` keep scheduling decisions consistent with the rest of the pod's placement rules.

**Example:** With 2 replicas and 2 worker nodes, you get 1 pod per node:

```bash
$ kubectl -n dev get pods -l app.kubernetes.io/name=subnetcalc-frontend -o wide
NAME                        NODE
subnetcalc-frontend-xxx     kind-local-worker
subnetcalc-frontend-yyy     kind-local-worker2
```
