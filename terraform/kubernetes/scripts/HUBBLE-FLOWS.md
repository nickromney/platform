# Hubble Flows

This document sits next to the Hubble helper scripts and shows the intended
workflow:

1. Check that you are talking to Hubble Relay rather than the Hubble UI.
2. Capture a representative traffic window.
3. Summarise the flows into stable workload edges.
4. Generate draft source policy manifests from those observed edges.
5. Render those source manifests into the checked-in `categories/` shape.

The scripts involved are:

- `./hubble-check-connection.sh`
- `./hubble-capture-flows.sh`
- `./hubble-summarise-flows.sh`
- `./hubble-generate-cilium-policy.sh`
- `./hubble-observe-cilium-policies.sh`
- `./render-cilium-policy-values.sh`

## Observe Bootstrap Wrapper

If you want the broad "super-script" flow rather than hand-piping each step,
use:

```bash
./hubble-observe-cilium-policies.sh \
  --since 5m \
  --iterations 3 \
  --row-threshold 100
```

That wrapper is for namespace-by-namespace observation bootstrap:

1. discover namespaces
2. capture short Hubble windows for each namespace
3. summarise ingress and egress traffic
4. fall back to namespace/entity aggregation when the workload edge set is too
   noisy
5. write candidate ingress and egress manifests under `.run/`

It chains `./hubble-capture-flows.sh` and `./hubble-summarise-flows.sh` for the
capture and summary stages.

By default it scans all namespaces and relies on `--exclude-namespace` only
when you want to trim noise from bootstrap runs.

On busy namespaces, the first knob to turn is `--since`. The default wrapper
run asks Hubble for three separate 5-minute windows per namespace, so start
smaller when a namespace is noisy:

```bash
./hubble-observe-cilium-policies.sh \
  --since 30s \
  --iterations 1 \
  --exclude-namespace argocd
```

Then rerun the noisy namespace on its own once you know you want it:

```bash
./hubble-observe-cilium-policies.sh \
  --namespace argocd \
  --since 30s \
  --iterations 1
```

The wrapper now also emits a heartbeat every 10 seconds while a capture or
summary helper is still running. Use `--progress-every 0` to disable that.
Each run report also records capture, summary, and generation elapsed seconds
per namespace so you can compare a baseline `--capture-strategy since` run
against an adaptive run on the same namespace and cluster.

For egress that Hubble classifies as `world`, the wrapper now prefers exact
observed external destinations in generated candidates:

- `toFQDNs` when Hubble exposes a stable destination name
- `toCIDRSet` when only an exact IP is available

Use `--world-egress-mode entity` when you explicitly want the older
`toEntities: world` fallback instead.

It does not call `./hubble-generate-cilium-policy.sh` for the final step.
That generator is still aimed at "take this one stable TSV summary and turn it
into a checked-in module example". The observe wrapper needs different behavior:
one candidate ingress policy and one candidate egress policy per namespace,
plus namespace/entity fallback when a short capture window is too noisy.

If you want one command that also promotes the generated candidates into the
module workflow, use:

```bash
./hubble-observe-cilium-policies.sh \
  --since 5m \
  --iterations 1 \
  --promote-to-module
```

That still keeps the full capture/summarise evidence under `.run/`, but it also
copies each generated candidate manifest into:

- `terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/<namespace>/`

and renders the matching Helm-style values file into:

- `terraform/kubernetes/cluster-policies/cilium/cilium-module/categories/<namespace>/`

Use `--module-root DIR` to promote into a different module checkout, and
`--force-module-overwrite` when rerunning the same observed candidate names.

## Two Outputs

There are two different places you can take Hubble evidence in this repo.

For experiments and portable examples:

- `terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/`
- `terraform/kubernetes/cluster-policies/cilium/cilium-module/categories/`

That path is useful when you want a self-contained example policy plus its
rendered `metadata + specs` equivalent.

For the Cilium policy tree that this repo actually ships:

- `terraform/kubernetes/cluster-policies/cilium/shared/`
- `terraform/kubernetes/cluster-policies/cilium/projects/`
- `terraform/kubernetes/cluster-policies/cilium/dev/`
- `terraform/kubernetes/cluster-policies/cilium/uat/`
- `terraform/kubernetes/cluster-policies/cilium/sit/`

That is "our" live Cilium layout:

- `shared/` for clusterwide and shared-platform guardrails
- `projects/` for reusable namespaced app bundles
- `dev/`, `uat/`, and `sit/` for environment overlays
- `*/overrides/` for namespace-local exceptions

So Hubble does not directly generate a final policy path for you. It gives you
evidence, and then you decide whether the result belongs in:

- a reusable module example under `cilium-module/`
- a reusable shipped bundle under `projects/`
- a namespace-local shipped exception under `dev/overrides/`, `uat/overrides/`,
  or `sit/overrides/`

## Relay First

For this repo's local kind cluster, bare invocation defaults to Hubble CLI
port-forward mode and uses `~/.kube/kind-kind-local.yaml` when it exists.

```bash
cd terraform/kubernetes/scripts

./hubble-check-connection.sh
```

If you are using a manually-created localhost tunnel instead:

```bash
kubectl -n kube-system port-forward service/hubble-relay 4245:4245
./hubble-check-connection.sh --server localhost:4245
```

If you point `--server` at a browser URL such as
`https://hubble.admin.127.0.0.1.sslip.io`, the checker should call out that you
have hit the Hubble UI/admin route rather than relay.

## Capture Then Summarise

Start broad enough to catch the traffic you care about, then narrow once you
know the relevant destination port or workload.

General pattern:

```bash
./hubble-capture-flows.sh \
  --since 15m \
  --to-namespace observability \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by workload \
      --direction egress
```

`--to-namespace` on the capture side and `--direction egress` on the
summariser side are complementary, not contradictory:

- `--to-namespace datadog` means "only keep flows whose destination endpoint is
  in `datadog`"
- `--direction egress` means "only keep Hubble rows where traffic is leaving
  the source side"

So that combination is the normal way to ask "which workloads are sending
traffic into `datadog`?"

For busy namespaces, do not run several auto-port-forwarding captures in
parallel unless you also give them distinct `--port-forward-port` values.

## Observed Example

A focused OTLP capture against the local cluster produced a clean, policy-grade
edge into `observability`:

```bash
./hubble-capture-flows.sh \
  --since 30m \
  --from-namespace dev \
  --to-namespace observability \
  -- --port 4318 \
  | ./hubble-summarise-flows.sh \
      --report edges \
      --aggregate-by workload \
      --direction egress
```

Output:

```text
count  direction  verdict    protocol  src_ns  src             dst_class  dst_ns         dst             dst_port
20     EGRESS     FORWARDED  tcp       dev     sentiment-api   workload   observability  otel-collector  4318
4      EGRESS     FORWARDED  tcp       dev     subnetcalc-api  workload   observability  otel-collector  4318
```

The equivalent `uat` query showed the same workload shape:

```bash
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

Output:

```text
count  direction  verdict    protocol  src_ns  src             dst_class  dst_ns         dst             dst_port
21     EGRESS     FORWARDED  tcp       uat     sentiment-api   workload   observability  otel-collector  4318
4      EGRESS     FORWARDED  tcp       uat     subnetcalc-api  workload   observability  otel-collector  4318
```

That is a good candidate for an example ingress policy on
`observability/otel-collector`.

## From Flows To Policy

To generate the checked-in `observability/otel-collector` example shape, feed
the combined `dev + uat` OTLP summary straight into the generator:

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

That command writes:

- `../cluster-policies/cilium/cilium-module/sources/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml`
- `../cluster-policies/cilium/cilium-module/categories/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml`

The generator resolves stable workload labels from the live cluster with
`kubectl` and produces a draft `CiliumNetworkPolicy` for each destination edge
group.

The generated selectors and ingress sources should already be policy-usable. The
metadata title and description are intentionally generic drafts, so refine those
by hand if you want the checked-in source file to read more naturally.

If you want to inspect or review the selector choices before generating, check
the live workload labels you actually have:

```bash
kubectl -n observability get deploy otel-collector -o json | jq '.metadata.labels'
kubectl -n dev get deploy sentiment-api -o json | jq '.metadata.labels'
kubectl -n dev get deploy subnetcalc-api -o json | jq '.metadata.labels'
kubectl -n uat get deploy sentiment-api -o json | jq '.metadata.labels'
kubectl -n uat get deploy subnetcalc-api -o json | jq '.metadata.labels'
```

For the local cluster, the stable selector pair was:

- destination: `k8s:app.kubernetes.io/name=otel-collector` in `observability`
- sources:
  - `k8s:app.kubernetes.io/name=sentiment-api` in `dev`
  - `k8s:app.kubernetes.io/name=subnetcalc-api` in `dev`
  - `k8s:app.kubernetes.io/name=sentiment-api` in `uat`
  - `k8s:app.kubernetes.io/name=subnetcalc-api` in `uat`

That generated manifest is the "module example" path. The repo's live policy
tree uses a different placement decision, shown below.

## How One Of Ours Comes Into Being

The concrete example in the shipped policy tree is:

- `../cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`

That file exists because the decision was:

- workload: `dev/subnetcalc-api`
- behaviour: background fetch of Cloudflare range data
- destination: `www.cloudflare.com:443`
- scope: `dev` only
- placement: namespace-local exception, not a reusable `projects/` policy

`uat` and `sit` intentionally do not carry that exception, so this belongs in:

- `terraform/kubernetes/cluster-policies/cilium/dev/overrides/`

not in:

- `terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/`

### Hubble Evidence For A World/FQDN Exception

The normal Hubble path for that kind of rule is:

1. find the DNS query
2. find the `world` egress
3. pin the exact host and port
4. decide whether it is reusable or namespace-local

Start with the workload and widen the time window if needed:

```bash
./hubble-capture-flows.sh \
  --since 30m \
  --from-namespace dev \
  --pod subnetcalc-api \
  --type l7 \
  | ./hubble-summarise-flows.sh \
      --report dns \
      --aggregate-by workload \
      --direction egress
```

Then look for the external destination:

```bash
./hubble-capture-flows.sh \
  --since 30m \
  --from-namespace dev \
  --pod subnetcalc-api \
  --world-only \
  | ./hubble-summarise-flows.sh \
      --report world \
      --aggregate-by workload \
      --direction egress
```

If there is no traffic in the current window, trigger the application path
first or widen `--since`. The important outcome is not a specific one-line
report format; it is the evidence that:

- `subnetcalc-api` is the source workload
- the destination hostname is `www.cloudflare.com`
- the port is `443/TCP`
- this is specific to `dev`

### Encode The Live Policy

Once you know it is a dev-only exception, the shipped-tree path is:

1. author `terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`
2. include it from `terraform/kubernetes/cluster-policies/cilium/dev/overrides/kustomization.yaml`
3. let `terraform/kubernetes/cluster-policies/cilium/dev/kustomization.yaml` pull in `overrides/`

That specific policy uses:

- a workload selector for `subnetcalc-api`
- a DNS proxy rule to kube-dns/CoreDNS
- `toFQDNs` pinned to `matchName: www.cloudflare.com`
- `toPorts` pinned to `443/TCP`

That is why the checked-in file looks the way it does.

### Validate The Shipped Tree

Once authored, validate the result as part of the real Cilium overlay tree:

```bash
kubectl kustomize terraform/kubernetes/cluster-policies/cilium/dev \
  | rg 'subnetcalc-cloudflare-live-fetch|www.cloudflare.com'
```

```bash
bats kubernetes/kind/tests/cilium-fqdn-policies.bats
```

Those checks prove:

- the policy is in the rendered dev overlay
- it is exact-host scoped to `www.cloudflare.com`
- it has no CIDR assist
- the FQDN policy carries its own DNS proxy rule

## Render The Category

`hubble-generate-cilium-policy.sh` already writes the matching rendered
`categories/` file alongside the source manifest it generates.

If you later edit the source manifest by hand, render the whole category again:

```bash
terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/observability/render.sh
```

That writes the rendered Helm-values-shaped output under:

- `../cluster-policies/cilium/cilium-module/categories/observability/cnp-observability-otel-collector-allow-otlp-from-app-workloads.yaml`

The source file is the authoring surface. The rendered category file is the
checked-in equivalent used when you want the `metadata + specs` values shape.

## Practical Loop

For a new namespace or external cluster experiment, the loop should be:

1. `./hubble-check-connection.sh`
2. `./hubble-capture-flows.sh ... | ./hubble-summarise-flows.sh ...`
3. tighten the query until the edge is stable at workload level
4. pipe `--format tsv` output into `./hubble-generate-cilium-policy.sh` when
   you want a draft module policy
5. inspect live labels with `kubectl ... -o json | jq` if you need to review or
   adjust selector choices
6. decide the destination:
   - `cilium-module/sources/` for an example or portable generated policy
   - `cluster-policies/cilium/shared|projects|<namespace>/overrides/` for the
     shipped tree
7. if you hand-edited a `cilium-module/` source file after generation, run that
   category's `render.sh`
8. if you changed the shipped tree, validate with `kubectl kustomize` and the
   nearest BATS coverage
9. commit both the evidence-driven source and the rendered or composed output
