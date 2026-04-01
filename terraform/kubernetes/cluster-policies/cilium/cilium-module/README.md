# Cilium Module Workflow

This module keeps raw source manifests under `sources/` and the rendered Helm
values shape under `categories/`.

- Edit or add raw Cilium manifests in `sources/<category>/`.
- Render the category after changes with the local `render.sh`.
- Commit both the source manifest and the rendered output in `categories/`.
- The category-local `render.sh` files are thin shims over
  `cilium-module/render-category.sh`, so the render logic stays in one place.

Examples:

```bash
terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/sandbox/render.sh
terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/observability/render.sh
terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/aks-sensible/render.sh
```

## Hubble-Assisted Policy Discovery

The two helper scripts below are meant for the workflow you described:

- `terraform/kubernetes/scripts/HUBBLE-FLOWS.md`
  - capture-to-policy notes that live next to the Hubble helper scripts
  - includes the observed `dev/uat -> observability/otel-collector:4318`
    example and the follow-on render step
- `terraform/kubernetes/scripts/hubble-check-connection.sh`
  - checks whether a relay endpoint is actually reachable
  - defaults to Hubble CLI port-forward mode in this repo
  - calls out the common mistake of pointing at the Hubble UI/admin route
    instead of the relay
- `terraform/kubernetes/scripts/hubble-capture-flows.sh`
  - wraps `hubble observe -o jsonpb`
  - accepts `--server` as:
    - a local relay address such as `localhost:4245`
    - an HTTPS front door such as `https://relay.example.com`
    - a TLS relay address such as `tls://relay.example.com:443`
  - this covers direct local port-forward access, Cloudflare tunnel hostnames,
    and Tailscale names
  - the endpoint must expose the Hubble Relay gRPC API itself, not the Hubble
    UI/admin route
  - defaults to the namespaces we actually ship if you do not pass explicit
    filters: `argocd`, `dev`, `kyverno`, `nginx-gateway`, `observability`
- `terraform/kubernetes/scripts/hubble-summarise-flows.sh`
  - turns raw `jsonpb` into deterministic traffic summaries
  - supports `edges`, `world`, `dns`, and `drops` reports
  - can aggregate by `workload` for policy authoring or `pod` for noisy
    namespaces such as `observability`
- `terraform/kubernetes/scripts/hubble-generate-cilium-policy.sh`
  - consumes `hubble-summarise-flows.sh --format tsv` output
  - resolves stable workload selectors with `kubectl`
  - writes draft manifests into `sources/<category>/`
  - writes the matching rendered file into `categories/<category>/`

The capture script writes newline-delimited JSON from `hubble observe -o jsonpb`
to stdout. The summariser reads that stream from stdin. This is not JSONP.

### Live Query Examples

For this cluster, the actual relay surfaces are:

- in-cluster service: `hubble-relay.kube-system.svc.cluster.local:4245`
- host-side CLI access: `localhost:4245` only after `hubble-capture-flows.sh -P`
  or a manual `kubectl port-forward service/hubble-relay 4245:4245`
- human web UI: `https://hubble.admin.127.0.0.1.sslip.io`

There is no shipped external relay hostname for this cluster today.

Raw Hubble query that works without pre-establishing a localhost tunnel:

```bash
hubble observe -P --kubeconfig ~/.kube/kind-kind-local.yaml --since 15m \
  --from-namespace dev --to-namespace observability
```

Raw Hubble query against an already forwarded relay:

```bash
hubble observe --server localhost:4245 --since 15m \
  --from-namespace dev --to-namespace observability
```

Check the relay path before capturing:

```bash
# This repo: explicit execution auto-port-forwards via ~/.kube/kind-kind-local.yaml
./hubble-check-connection.sh --execute

# This repo: manual relay port-forward already in place
kubectl -n kube-system port-forward service/hubble-relay 4245:4245
./hubble-check-connection.sh --execute --server localhost:4245

# Remote relay over Cloudflare/Tailscale
./hubble-check-connection.sh --execute --server https://relay.example.com
```

Examples of supported access patterns with the wrapper:

```bash
# Examples below assume you are already in terraform/kubernetes/scripts/.
# This cluster: works without a pre-existing localhost port-forward
./hubble-capture-flows.sh \
  -P --kubeconfig ~/.kube/kind-kind-local.yaml \
  --since 15m \
  --namespace observability

# This cluster: manual relay port-forward on the host first
kubectl -n kube-system port-forward service/hubble-relay 4245:4245
./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 15m \
  --namespace dev \
  --namespace observability

# Generic remote relay examples for work systems
./hubble-capture-flows.sh \
  --server https://relay.example.com \
  --since 15m \
  --namespace observability

./hubble-capture-flows.sh \
  --server https://hubble.tailnet.ts.net:4443 \
  --tls-server-name hubble.tailnet.ts.net --since 15m --namespace argocd

./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 10m \
  --from-namespace dev --to-namespace observability \
  | ./hubble-summarise-flows.sh \
      --report edges --aggregate-by workload --direction egress

./hubble-capture-flows.sh \
  -P --kubeconfig ~/.kube/kind-kind-local.yaml \
  --from-namespace dev --to-namespace observability --last 100
```

If the remote endpoint terminates TLS with a non-default certificate chain or a
certificate name that does not match the public hostname, pass the extra TLS
flags through the wrapper:

```bash
./hubble-capture-flows.sh \
  --server https://hubble.example.com:4443 \
  --tls-server-name hubble.hubble-relay.cilium.io \
  --tls-ca-cert-file ./hubble-ca.crt \
  --since 15m \
  --namespace observability
```

Important:

- In this repo, `https://hubble.admin.127.0.0.1.sslip.io` is the Hubble UI
  served through the admin gateway and `oauth2-proxy`, not the Hubble Relay
  gRPC API.
- For local use here, prefer `hubble-capture-flows.sh -P`.
- Use `localhost:4245` only after you already have a local
  `kubectl -n kube-system port-forward service/hubble-relay 4245:4245`.
- For Cloudflare tunnel or Tailscale on a work system, point the wrapper at a
  tunnel that exposes `hubble-relay` itself rather than the Hubble UI hostname.

Capture and summarise the same traffic as stable workload edges:

```bash
./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 15m \
  --from-namespace dev \
  --to-namespace observability \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by workload \
      --direction egress
```

Switch to pod granularity when a namespace is too busy and you need to see the
replica-level noise:

```bash
./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 10m \
  --namespace observability \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by pod \
      --direction egress
```

Useful focused reports:

```bash
# What is talking to world?
./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 15m \
  --namespace argocd \
  --namespace nginx-gateway \
  | ./hubble-summarise-flows.sh \
      --report world \
      --direction egress

# Which DNS names are being queried?
./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 15m \
  --namespace dev \
  | ./hubble-summarise-flows.sh \
      --report dns \
      --aggregate-by workload

# What is getting dropped?
./hubble-capture-flows.sh \
  --server localhost:4245 \
  --since 15m \
  --namespace nginx-gateway \
  | ./hubble-summarise-flows.sh \
      --report drops
```

### Workload Identification

For policy authoring, start with workload aggregation, then confirm the stable
selector labels on the matching workload or pods:

```bash
kubectl get pods -n observability \
  -L app.kubernetes.io/name,app.kubernetes.io/component,k8s-app,app

kubectl get deploy,ds,sts -n observability --show-labels

kubectl get pod -n observability <pod-name> -o json | jq '.metadata.labels'
```

The Hubble `jsonpb` output includes both the pod name and the inferred
`workloads[]` owner, plus the endpoint labels that usually become the policy
selector. Avoid writing policies against pod names unless you are intentionally
debugging one broken replica.

### Example Synthesis

A live query against the local `kind-kind-local` cluster showed the expected
`dev -> observability` pattern:

- `sentiment-api` and `subnetcalc-api` in `dev`
- egressing to `observability/otel-collector`
- on `4318/TCP`

That is the kind of stable edge the summariser is designed to emit for policy
authoring.

The checked-in `observability` example in this module was derived from that
workflow with focused OTLP queries:

```bash
cd terraform/kubernetes/scripts

./hubble-capture-flows.sh \
  --since 30m \
  --from-namespace dev \
  --to-namespace observability \
  -- --port 4318 \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by workload \
      --direction egress

./hubble-capture-flows.sh \
  --since 30m \
  --from-namespace uat \
  --to-namespace observability \
  -- --port 4318 \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by workload \
      --direction egress
```

Those observed edges were then encoded as:

- `sources/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml`
- `categories/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml`

The draft module policy can now be generated directly from the summarised TSV:

```bash
./hubble-capture-flows.sh \
  --since 30m \
  --from-namespace dev \
  --from-namespace uat \
  --to-namespace observability \
  -- --port 4318 \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by workload \
      --direction egress \
      --format tsv \
  | ./hubble-generate-cilium-policy.sh \
      --category observability \
      --policy-name cnp-observability-otel-collector-allow-otlp-from-app-workloads
```

That generator output is a draft. The selectors and port rules come from live
Hubble evidence plus `kubectl` label resolution, while the title and
description may still need a short manual polish before commit.

### Turn Traffic Into Policy

Once the edge is stable:

1. Capture a time window with representative traffic.
2. Summarise with `--aggregate-by workload --format tsv`.
3. Pipe the TSV into `hubble-generate-cilium-policy.sh` for a draft
   `sources/<category>/` manifest plus its rendered `categories/<category>/`
   equivalent.
4. Re-run with `--aggregate-by pod` only if a busy namespace needs deeper
   inspection.
5. Check `world`, `dns`, and `drops` before granting any broad exception.
6. If you refine the generated source file by hand, run the category `render.sh`
   so `categories/<category>/` stays in sync.
