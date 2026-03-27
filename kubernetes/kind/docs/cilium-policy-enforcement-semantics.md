# Cilium Policy Enforcement Semantics

This note answers one specific question:

If you add one explicit allow policy for one workload, do you accidentally
block unrelated traffic from other workloads?

Short answer:

- no, not by default for other workloads
- yes, for the selected workload and direction, if that workload was not
  already in default-deny for that direction
- in this repo's kind cluster, most application pods are already in both
  ingress and egress default-deny because of the shared
  `application-baseline` policy

Official Cilium policy semantics:

- allow policies are additive
- deny policies take precedence over allow policies
- default-deny is enabled per direction when an endpoint is selected by a
  policy containing that direction's section

References:

- [Cilium policy language](https://docs.cilium.io/en/stable/security/policy/language/)
- [Cilium layer 3 policy examples](https://docs.cilium.io/en/stable/security/policy/language.html)

## The Rule To Remember

Think about Cilium enforcement as:

1. per endpoint
2. per direction
3. union of all matching allow rules

That means:

- an `ingress` rule changes ingress enforcement for the endpoints it selects
- an `egress` rule changes egress enforcement for the endpoints it selects
- a rule selecting `dev/subnetcalc-frontend` does not directly change
  `dev/sentiment-api`
- a deny is not required to block unmatched traffic once the endpoint is in
  default-deny for that direction

In practice:

- if a pod is selected by any `egress` policy, only the union of matching
  allowed egress remains
- if a pod is selected by any `ingress` policy, only the union of matching
  allowed ingress remains
- if you need to subtract from an existing allow set, use `ingressDeny` or
  `egressDeny`

## What This Cluster Is Doing Right Now

The key local policy is
[`application-baseline.yaml`](/Users/nickromney/Developer/personal/platform/terraform/kubernetes/cluster-policies/cilium/shared/application-baseline.yaml).

It selects every pod in namespaces labeled
`platform.publiccloudexperiments.net/namespace-role=application`, which here
means `dev`, `sit`, and `uat`.

That policy contains both:

- `ingress`
- `egress`

So every selected application pod is already in:

- ingress default-deny
- egress default-deny

with these baseline allowances:

- ingress from `host` and `remote-node` for kubelet/node plumbing
- egress to DNS in `kube-system`
- egress to the Kubernetes API
- egress to the `default/kubernetes` service on `443`

This is the most important local fact for your question: adding one more allow
policy in `dev` is usually widening an existing restricted set, not creating
restriction from scratch.

## Your Concrete Example

You asked:

If I allow `dev/subnetcalc-frontend` out to `observability`, have I limited the
ability of `sentiment-api` to get there too?

Answer:

- no, not if your new policy only selects `subnetcalc-frontend`
- `sentiment-api` keeps whatever union of rules already matches
  `sentiment-api`
- the policy surface is endpoint-specific, not namespace-global in that way

What matters is the selector.

If you write a policy like this:

```yaml
endpointSelector:
  matchLabels:
    "k8s:app.kubernetes.io/name": subnetcalc-frontend
egress:
  ...
```

then only `subnetcalc-frontend` pods are affected by that policy.

`sentiment-api` is unaffected unless:

- another policy selects it too
- or a broader clusterwide policy selects both workloads
- or a deny policy selects it

## Why `prometheus*` Is Probably The Wrong Path Here

In this cluster, the current `observability` ingress policy is in
[`observability-hardened.yaml`](/Users/nickromney/Developer/personal/platform/terraform/kubernetes/cluster-policies/cilium/shared/observability-hardened.yaml).

That policy allows application namespaces into `observability` on:

- `4317/TCP`
- `4318/TCP`

Those are the OTEL collector ports.

The live services in `observability` are:

- `otel-collector` on `4317` and `4318`
- `prometheus-server` on `80`
- `grafana` on `3000`
- node-exporter and kube-state-metrics on their own metrics ports

So for this cluster:

- `app -> observability/otel-collector:4317|4318` is the intended push path
- `observability/prometheus -> app metrics endpoint` is the intended scrape path
- `app -> observability/prometheus-server` is probably not the path you want

## What `sentiment-api` Is Doing

`sentiment-api` already has an explicit egress policy in
[`sentiment-runtime.yaml`](/Users/nickromney/Developer/personal/platform/terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml):

- policy name: `sentiment-api-egress`
- destination: `observability`
- selector: `app.kubernetes.io/name=otel-collector`
- ports: `4317` and `4318`

So `sentiment-api` already has its own extra egress allowance to observability.

That means a new policy for `subnetcalc-frontend` does not replace
`sentiment-api-egress`. They are independent because they select different
pods.

## What `subnetcalc-frontend` Is Doing

`subnetcalc-frontend` currently has:

- the shared `application-baseline` policy
- `subnetcalc-frontend-ingress`

The frontend ingress policy allows the router to reach the frontend on `8080`,
but there is no checked-in frontend egress allow to observability right now.

So if you add a new policy selecting only `subnetcalc-frontend` and allowing
egress to `otel-collector:4317|4318`, the effect is:

- `subnetcalc-frontend` gains that additional egress path
- `subnetcalc-frontend` does not gain broad access to all of `observability`
- `sentiment-api` is unchanged

## A Small Matrix

Current local behavior, simplified:

| Workload | Already in ingress default-deny? | Already in egress default-deny? | Extra observability allow today? |
| --- | --- | --- | --- |
| `dev/sentiment-api` | yes | yes | yes, to `otel-collector:4317,4318` |
| `dev/subnetcalc-frontend` | yes | yes | no explicit extra allow today |
| `dev/subnetcalc-api` | yes | yes | no explicit extra allow today |

So if you add:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: subnetcalc-frontend-otel-egress
  namespace: dev
spec:
  endpointSelector:
    matchLabels:
      "k8s:project": kindlocal
      "k8s:team": dolphin
      "k8s:app": subnetcalc
      "k8s:tier": frontend
      "k8s:app.kubernetes.io/name": subnetcalc-frontend
  egress:
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": observability
            "k8s:app.kubernetes.io/name": otel-collector
      toPorts:
        - ports:
            - port: "4317"
              protocol: TCP
            - port: "4318"
              protocol: TCP
```

the result is:

- `subnetcalc-frontend` now can reach the OTEL collector
- `sentiment-api` still can reach the OTEL collector because of its own policy
- `subnetcalc-frontend` still cannot reach arbitrary destinations in
  `observability`
- `sentiment-api` is not narrowed by this new policy

## When You Would Need A Deny

You only need a deny when "no matching allow" is not enough.

Examples:

- you already have a broad allow and want to carve out one forbidden target
- you want to block one FQDN/IP/namespace even if another allow would permit it
- you want a policy outcome that must override future additive allow rules

If there is no matching allow for a selected endpoint in a direction, traffic
is already blocked. No deny is required for that.

## How To Think About This Safely

Before adding a new policy, ask:

1. Which exact pods does `endpointSelector` select?
2. Is this an `ingress` change, an `egress` change, or both?
3. Are those pods already selected by another policy in that direction?
4. Is this widening an existing allow set, or creating the first allow in that
   direction?

For this repo's app namespaces, the answer to 3 is usually already "yes"
because of `application-baseline`.

## Good Checks Before You Apply

Inspect the policies:

```bash
kubectl get ccnp application-baseline -o yaml
kubectl get ccnp observability-hardened -o yaml
kubectl get cnp -n dev sentiment-api-egress -o yaml
kubectl get cnp -n dev subnetcalc-frontend-ingress -o yaml
```

Inspect the actual services:

```bash
kubectl get svc -n observability -o wide
kubectl get svc -n dev -o wide
```

Observe the current path in Hubble:

```bash
hubble observe \
  --server localhost:4246 \
  --from-pod dev/sentiment-api \
  --to-namespace observability \
  --since 15m \
  --last 100 \
  --output compact
```

If you want, the next step can be a checked-in example policy for
`subnetcalc-frontend -> observability/otel-collector` in `dev`, plus the
matching Hubble commands to validate that it widens only that frontend's egress.
