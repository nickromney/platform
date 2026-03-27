# Cilium And Hubble Starting Point

This note captures a live baseline from the local `kind-kind-local` cluster on
March 27, 2026 and turns it into a repeatable workflow for:

- proving what traffic already exists before tightening policy
- using Hubble to drill into that traffic with concrete selectors
- running `cilium connectivity test` without losing track of its temporary
  namespaces
- sketching tighter policies for a different cluster, including a future
  Datadog namespace

This file is deliberately split into:

- local kind facts that were observed here
- generic Hubble/Cilium commands you can reuse on a stricter cluster

See also:

- [cilium-policy-enforcement-semantics.md](/Users/nickromney/Developer/personal/platform/kubernetes/kind/docs/cilium-policy-enforcement-semantics.md)

## Local Kind Baseline

Captured against:

```bash
export KUBECONFIG="$HOME/.kube/kind-kind-local.yaml"
kubectl config current-context
```

Observed on March 27, 2026:

- cluster context: `kind-kind-local`
- Cilium: `1.19.2`
- `cilium-cli`: `v0.19.2`
- Hubble CLI: `v1.18.6`
- Hubble Relay: healthy
- namespaces: `21`
- pods: `71`
- deployments: `51`
- namespaced `CiliumNetworkPolicy` objects: `28`
- clusterwide `CiliumClusterwideNetworkPolicy` objects: `22`

Namespace roles currently present on the local kind cluster:

| Role | Namespaces |
| --- | --- |
| application | `dev`, `sit`, `uat` |
| shared | `apim`, `gateway-routes`, `observability`, `platform-gateway`, `sso` |
| platform | `argocd`, `cert-manager`, `gitea`, `headlamp`, `kyverno`, `nginx-gateway`, `policy-reporter` |
| other/core | `default`, `kube-system`, `kube-public`, `kube-node-lease`, `local-path-storage`, `cilium-secrets` |

Important local fact: there is no `datadog` namespace in this environment.
Any Datadog policy examples below are generic starters, not examples observed on
this cluster.

Another important local fact: this cluster is not an allow-all baseline. Hubble
already showed denied flows, for example `observability/prometheus-server` to
`nginx-gateway:9113`. Use the local kind cluster as a workflow reference, not
as proof that another cluster is currently permissive.

## Baseline Inventory Commands

Run these first and save the output before tightening anything:

```bash
export KUBECONFIG="$HOME/.kube/kind-kind-local.yaml"

kubectl get ns --show-labels
kubectl get pods -A -o wide
kubectl get deploy -A -o wide
kubectl get ciliumnetworkpolicies -A
kubectl get ciliumclusterwidenetworkpolicies
cilium status --kubeconfig "$KUBECONFIG"
KUBECONFIG="$KUBECONFIG" kubernetes/kind/scripts/audit-bootstrap.sh
```

The bootstrap audit is useful, but noisy. It reports all existing restarts,
older warning events, and previous logs. Treat it as a broad cluster snapshot,
then use `kubectl` plus Hubble for the focused diff you care about.

## Hubble Setup That Worked Reliably Here

`hubble status -P --kubeconfig "$KUBECONFIG"` worked, but repeated
`hubble observe -P ...` calls were flaky because port `4245` was sometimes
already in use. The most reliable local pattern was an explicit port-forward:

```bash
export KUBECONFIG="$HOME/.kube/kind-kind-local.yaml"

kubectl -n kube-system port-forward service/hubble-relay 4246:80
```

Then use:

```bash
hubble status --server localhost:4246
```

The local CLI also warned that the Hubble CLI is older than Relay:

- Hubble CLI: `1.18.6`
- Hubble Relay: `1.19.2`

That mismatch did not stop basic observation, but it is worth fixing if you
want fewer surprises.

## Hubble Queries Worth Memorizing

The following selectors are the ones that matter when moving from "what is
happening?" to "what do I actually allow?"

All traffic touching one namespace:

```bash
hubble observe \
  --server localhost:4246 \
  --namespace sandbox \
  --since 15m \
  --last 100 \
  --output compact
```

Traffic from one specific pod:

```bash
hubble observe \
  --server localhost:4246 \
  --from-pod sandbox/frontend \
  --since 15m \
  --last 100 \
  --output compact
```

Frontend to backend, using labels instead of pod names:

```bash
hubble observe \
  --server localhost:4246 \
  --from-label 'k8s:io.kubernetes.pod.namespace=sandbox' \
  --from-label 'k8s:app.kubernetes.io/component=frontend' \
  --to-label 'k8s:io.kubernetes.pod.namespace=sandbox' \
  --to-label 'k8s:app.kubernetes.io/component=backend' \
  --since 15m \
  --last 100 \
  --output compact
```

Anything dropped, with policy names where available:

```bash
hubble observe \
  --server localhost:4246 \
  --verdict DROPPED \
  --since 15m \
  --last 100 \
  --output compact \
  --print-policy-names
```

FQDN-focused egress review for a sensitive ingress namespace:

```bash
hubble observe \
  --server localhost:4246 \
  --from-namespace ingress \
  --to-fqdn login.microsoftonline.com \
  --since 30m \
  --last 100 \
  --output compact
```

HTTP/L7 queries when the path is proxied through an L7-aware policy:

```bash
hubble observe \
  --server localhost:4246 \
  --from-namespace sandbox \
  --to-namespace sandbox \
  --protocol http \
  --http-method GET \
  --http-path '/api/.*' \
  --since 15m \
  --last 100 \
  --output compact
```

Two local examples that returned useful output here:

```bash
hubble observe \
  --server localhost:4246 \
  --from-pod cilium-test-1/client \
  --since 5m \
  --last 20 \
  --output compact
```

That showed:

- DNS from `cilium-test-1/client` to `kube-system/coredns`
- forwarded TCP traffic from `cilium-test-1/client` to `cilium-test-1/l7-lb`
- forwarded TCP traffic from `cilium-test-1/client` to `cilium-test-1/echo-same-node`

```bash
hubble observe \
  --server localhost:4246 \
  --verdict DROPPED \
  --since 15m \
  --last 20 \
  --output compact \
  --print-policy-names
```

That showed existing denied traffic elsewhere in the cluster, including
`observability/prometheus-server` attempts to reach `nginx-gateway:9113`.

## Connectivity Test Workflow

### The straightforward run

```bash
export KUBECONFIG="$HOME/.kube/kind-kind-local.yaml"
cilium connectivity test --kubeconfig "$KUBECONFIG" --ip-families ipv4
```

Why `ipv4` was used here:

- the local kind cluster is single-stack in practice
- it removes avoidable noise from the run

### What appeared during the local run

The connectivity test created these namespaces:

- `cilium-test-1`
- `cilium-test-ccnp1`
- `cilium-test-ccnp2`

The main namespace contained temporary deployments and services such as:

- `client`
- `client2`
- `echo-same-node`
- `l7-lb`
- `l7-lb-non-l7`

Useful inspection commands during the run:

```bash
kubectl get ns | rg '^cilium-test'
kubectl get all -n cilium-test-1
kubectl get pods -n cilium-test-1 --show-labels
```

Observed labels that are useful if you need to find the test artifacts again:

- test namespaces carried `app.kubernetes.io/name=cilium-cli`
- `cilium-test-1` pods carried labels like:
  - `kind=client`
  - `kind=echo`
  - `kind=l7-lb`
- `cilium-test-ccnp1` and `cilium-test-ccnp2` pods carried `kind=ccnp`

### Local gotchas

The first local run revealed two things worth documenting:

1. `cilium-cli` could not use Hubble Relay automatically here.

It logged:

- `Unable to contact Hubble Relay, disabling Hubble telescope and flow validation`

Manual Relay port-forwarding plus `hubble observe` still worked fine.

2. `--post-test-sleep` sleeps after each test case, not only once at the end.

This command:

```bash
cilium connectivity test \
  --kubeconfig "$KUBECONFIG" \
  --ip-families ipv4 \
  --post-test-sleep 60s
```

turned into a very long run because the suite paused for `60s` after each test
case. Use it sparingly.

## Enforced Starter Pack On Live `cilium-test` Workloads

This repo now includes an actual starter pack entry at:

- `terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/cilium-connectivity-test/cilium-connectivity-test-starter.yaml`
- `terraform/kubernetes/cluster-policies/cilium/cilium-module/categories/cilium-connectivity-test/cilium-connectivity-test-starter.yaml`

It is intentionally narrow:

- it only selects namespaces created by `cilium-cli` via the namespace label
  `app.kubernetes.io/name=cilium-cli`
- it only targets pods with `kind=client`, `kind=echo`, and `kind=l7-lb`
- it does not touch the normal application, shared, or platform namespaces

The live workflow used here was:

```bash
export KUBECONFIG="$HOME/.kube/kind-kind-local.yaml"

cilium connectivity test \
  --kubeconfig "$KUBECONFIG" \
  --ip-families ipv4 \
  --test no-policies \
  --post-test-sleep 300s

kubectl apply -f \
  terraform/kubernetes/cluster-policies/cilium/cilium-module/sources/cilium-connectivity-test/cilium-connectivity-test-starter.yaml
```

### What broke first

The first version of the starter pack only allowed destination-side ingress to
`echo` and `l7-lb`.

That was not enough.

Hubble showed the client pod entering policy mode and then dropping its own
egress SYN packets:

- `cilium-test-1/client -> echo-same-node:8080` `EGRESS DENIED`
- `cilium-test-1/client -> l7-lb:8080` `EGRESS DENIED`

That is the exact behavior to remember: once a pod is selected by policy, a
single-sided allow is often not enough. If you want a path to survive, you
usually need the source egress rule and the destination ingress rule.

### What worked after the fix

The corrected starter pack added the missing client egress rule to match the
existing destination ingress rule.

After re-applying the policy, these commands succeeded:

```bash
kubectl exec -n cilium-test-1 deploy/client -- \
  curl -sS -o /dev/null -m 5 -w 'echo=%{http_code}\n' \
  http://echo-same-node:8080/

kubectl exec -n cilium-test-1 deploy/client -- \
  curl -sS -o /dev/null -m 5 -w 'l7=%{http_code}\n' \
  http://l7-lb:8080/

kubectl exec -n cilium-test-1 deploy/client -- \
  curl -sk -o /dev/null -m 5 -w 'api=%{http_code}\n' \
  https://kubernetes.default.svc.cluster.local
```

Observed results:

- `echo=200`
- `l7=200`
- `api=403`

The `403` from the Kubernetes API is useful here: it proves the path is still
reachable, and the denial is coming from Kubernetes authn/authz rather than
from network policy.

This command stayed denied:

```bash
kubectl exec -n cilium-test-1 deploy/client -- \
  curl -sS -o /dev/null -m 5 -w 'world=%{http_code}\n' \
  https://example.com
```

Observed result:

- `world=000`
- curl timed out after `5s`

### What Hubble showed after the fix

The corrected policy produced the exact pattern you want for a safe starter
pack:

- DNS egress allowed by `cilium-connectivity-test-starter`
- kube-apiserver egress allowed by `cilium-connectivity-test-starter`
- `client -> echo-same-node:8080` showed both:
  - `EGRESS ALLOWED BY cilium-connectivity-test-starter`
  - `INGRESS ALLOWED BY cilium-connectivity-test-starter`
- `client -> l7-lb:8080` showed both:
  - `EGRESS ALLOWED BY cilium-connectivity-test-starter`
  - `INGRESS ALLOWED BY cilium-connectivity-test-starter`
- `client -> example.com:443` still showed:
  - `EGRESS DENIED`
  - `Policy denied DROPPED`

That gives you a real demonstration workflow:

1. create only the `cilium-test` workloads
2. apply the narrow starter pack
3. confirm the intended safe paths are still allowed
4. confirm that unrelated egress is actually denied
5. use Hubble to prove both outcomes

## Connectivity Test Cleanup

When the run is interrupted, or if you just want to clear the artifacts
manually, delete the three namespaces:

```bash
kubectl delete ns cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2 --wait=false
```

Then confirm cleanup in three passes:

```bash
kubectl get pods -A | rg 'cilium-test' || true
kubectl get ns | rg '^cilium-test' || true
KUBECONFIG="$KUBECONFIG" kubernetes/kind/scripts/audit-bootstrap.sh \
  | rg 'cilium-test|^== Context ==|^== Pods ==|^== Non-Running Pods ==|^OK   All pods are Running or Completed|^WARN '
```

What happened locally:

- the test pods disappeared first
- the namespaces stayed in `Terminating` briefly
- a short time later, `kubectl get ns | rg '^cilium-test'` returned nothing
- the filtered audit output no longer showed any `cilium-test` entries

## Policy Authoring Order For A Stricter Cluster

For a stricter cluster, the safest order is:

1. inventory namespaces, pods, deployments, and existing Cilium policies
2. run Hubble in observe mode long enough to capture real traffic
3. translate that traffic into specific allow rules
4. leave the ingress namespace until last

A practical sequence:

1. Capture `15m` to `30m` of Hubble output for each namespace pair you care about.
2. Start with obvious app-to-app flows such as `sandbox frontend -> sandbox backend`.
3. Add shared-service flows next, such as application workloads to a future
   Datadog or OTEL collector namespace.
4. Only after those are explicit should you restrict `ingress` egress to
   exact FQDNs and IPs.

## Policy Sketches

These examples are not for the local kind cluster. They are starting points for
a stricter cluster.

### Sandbox frontend to sandbox backend

This is the smallest useful app-to-app rule: select the backend, then allow
only frontend ingress on the port you actually use.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: sandbox-frontend-to-backend
  namespace: sandbox
spec:
  endpointSelector:
    matchLabels:
      "k8s:app.kubernetes.io/component": backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": sandbox
            "k8s:app.kubernetes.io/component": frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

Tighten this further by replacing `component=frontend` with the exact app label
you trust.

### Sandbox workloads egress to a future Datadog namespace

This is the egress-side rule. It is intentionally separate from the Datadog
ingress-side rule.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: sandbox-to-datadog-apm
  namespace: sandbox
spec:
  endpointSelector:
    matchExpressions:
      - key: "k8s:app.kubernetes.io/component"
        operator: In
        values:
          - frontend
          - backend
          - gateway
  egress:
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": datadog
      toPorts:
        - ports:
            - port: "8126"
              protocol: TCP
```

`8126` is the common Datadog APM agent port. Confirm the exact port and
selector labels in your cluster before applying it.

### Datadog ingress from in-cluster workloads only

This is the inverse rule on the Datadog side. It accepts traffic from pods
inside the cluster, but not from `world`.

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: datadog-apm-ingress
spec:
  endpointSelector:
    matchLabels:
      "k8s:io.kubernetes.pod.namespace": datadog
  ingress:
    - fromEntities:
        - host
        - remote-node
    - fromEndpoints:
        - matchExpressions:
            - key: "k8s:io.kubernetes.pod.namespace"
              operator: Exists
      toPorts:
        - ports:
            - port: "8126"
              protocol: TCP
```

If "anything in-cluster" is still too broad, replace the `fromEndpoints`
selector with your namespace-role labels so only app namespaces are allowed.

### Ingress namespace egress by exact FQDN and IP

This should be the late-stage hardening step, because it is easy to break.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ingress-egress-allowlist
  namespace: ingress
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": kube-system
            "k8s:k8s-app": kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
          rules:
            dns:
              - matchName: login.microsoftonline.com
              - matchName: api.example.com
    - toFQDNs:
        - matchName: login.microsoftonline.com
        - matchName: api.example.com
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toCIDRSet:
        - cidr: 203.0.113.10/32
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

Before writing that rule, collect the evidence first:

```bash
hubble observe \
  --server localhost:4246 \
  --from-namespace ingress \
  --traffic-direction egress \
  --since 30m \
  --last 200 \
  --output compact

hubble observe \
  --server localhost:4246 \
  --from-namespace ingress \
  --to-fqdn '*' \
  --since 30m \
  --last 200 \
  --output compact
```

## Why The `cilium-connectivity-test` Module Entry Is Safe To Use

The starter pack intentionally changes the traffic matrix, but only for the
temporary `cilium-test` workloads created by `cilium-cli`.

That makes it useful as a safe demo because:

- the policy is enforced on real workloads
- Hubble shows allowed and denied flows immediately
- normal app, shared-service, and ingress namespaces stay untouched

Treat it as a safe proving ground before tightening the real namespaces.

## References

- [Cilium troubleshooting: observing flows with Hubble Relay](https://docs.cilium.io/en/stable/operations/troubleshooting/)
- [Hubble CLI reference](https://docs.cilium.io/en/stable/observability/hubble/hubble-cli/)
- [Cilium connectivity test command reference](https://docs.cilium.io/en/stable/cmdref/cilium_connectivity_test/)
- [Simon Willison on Showboat and Rodney](https://simonwillison.net/2026/Feb/10/showboat-and-rodney/)
- [Datadog APM troubleshooting mentioning port 8126](https://docs.datadoghq.com/es/tracing/troubleshooting/connection_errors/)
