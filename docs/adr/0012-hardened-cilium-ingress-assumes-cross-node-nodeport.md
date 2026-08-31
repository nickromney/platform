# ADR 0012: Hardened Cilium ingress policies assume cross-node NodePort routing

- Status: Accepted
- Recorded: 2026-08-31

## Context

The hardened `CiliumClusterwideNetworkPolicy` set admits only node identities on
ingress. Dumping the live policy for the platform gateway endpoint shows:

```text
"L3": [ {"reserved:host"}, {"reserved:remote-node"}, {"reserved:aggregate-remote-node"} ]
```

There is no `reserved:world`. `argocd-hardened`, `gitea-hardened`,
`nginx-gateway-hardened` and `platform-gateway-hardened` all carry the same
`fromEntities: ["host", "remote-node"]`.

That works today only because of a property nothing states: the kind
control-plane node carries `node-role.kubernetes.io/control-plane:NoSchedule`,
so all 49 workload pods land on the worker while the `extraPortMappings` live on
the control-plane. **Every ingress request is therefore forced across a node
boundary**, and the source resolves to a node identity the policy admits.

Traffic that does not cross a node boundary resolves to `reserved:world`. The
Docker bridge gateway `172.18.0.1` is absent from the Cilium ipcache, so it
falls to the `0.0.0.0/0 -> identity=2` catch-all, and identity 2 is
`reserved:world`.

This surfaced when `worker_count = 0` was trialled for memory reasons. A
single-node cluster must remove the control-plane taint or nothing schedules, so
workloads land on the port-mapped node and the cross-node hop disappears.

## Resolution

The policies were fixed to match their own stated intent. `platform-gateway-hardened`
now admits `world` **scoped to :443 only**, and `gitea-hardened` gained a separate
`world` rule scoped to its published NodePorts (3000, 22, 2222) rather than
widening its existing unrestricted host/remote-node rule.

This is additive and topology-independent: single-node's `world` source becomes
admitted, two-node's node-identity source is untouched. Verified both ways --
`gitea :30090` from the host on a single node went from HTTP 000 to **200**, no
policy drops are recorded for any request, and a two-node stage-900 apply with the
fix completed `exit=0` with `subnetcalc.dev` still returning 302.

Single-node is still not fully serviceable, but for a **different and unrelated**
reason: the gateway's TLS handshake over the host 443 mapping resets
(`client closed connection while SSL handshaking` in nginx, `Recv failure` in
curl) while plain HTTP on gitea's NodePort succeeds. eth0 inside the kind node has
MTU 65535 and the Cilium interfaces 65520, so the leading hypothesis is that the
large TLS certificate flight does not survive the path to the host while small
packets do. That is untested.

## Decision

Treat the two-node topology as a **load-bearing precondition of the hardened
policies**, not an incidental default. `worker_count = 0` stays available and
tested but is not part of any shipped resource profile.

Do not widen the policies to admit `reserved:world`, and do not hardcode the
kind bridge CIDR into them. Both trade away the property the "hardened" name
promises in order to paper over a routing detail.

## Consequences

- `local-8gb` keeps the stock topology. The measured cost is small: single-node
  saved roughly 117 Mi of actual usage, against 24 removed pods doing the real
  work.
- The kubeadm `nodeRegistration.taints: []` patch, the operator-override
  precedence fix and `node_topology.tftest.hcl` all remain, so `worker_count = 0`
  still builds and untaints correctly for anyone who opts in deliberately.
- Any future change that co-locates workloads with the port-mapped node -- a
  single-node profile, a scheduling change, a taint removal -- reintroduces this
  failure. It presents as a hung connection, not a policy error, which is why it
  is worth recording.

## Evidence

Reproduced on a **two-node** cluster by moving only the gateway pod, holding
node count and policy constant:

| gateway pod placement | `subnetcalc.dev` |
| --- | --- |
| worker (cross-node from ingress) | HTTP 302 |
| control-plane (same node as port mappings) | HTTP 000 |
| moved back to worker | HTTP 302 |

`cilium-dbg monitor --type drop` during the failing case:

```text
xx drop (Policy denied) ... identity world->1085: 10.244.0.97 -> 10.244.0.42:443 tcp SYN
```

Cilium reserved identities on this cluster: `1 = reserved:host`,
`2 = reserved:world`, `6 = reserved:remote-node`.

Enabling Cilium's kube-proxy replacement (`cilium_kube_proxy_replacement = true`,
which also sets kind's `kubeProxyMode: "none"`) does **not** fix this. Cilium's
NodePort translation works correctly -- it rewrites `:30070` to the gateway pod --
and the packet is then denied at the endpoint for exactly the same reason:

```text
identity world->21996: 172.18.0.1:61236 -> 10.244.0.91:443 tcp SYN   (host)
identity world->21996: 172.18.0.3:44970 -> 10.244.0.91:443 tcp SYN   (sibling container)
```

Source `172.18.0.1` is the Docker bridge gateway; `172.18.0.3` is another
container on the kind network. Both are `world`. The identity is decided by the
**source address**, not by which component performs the NodePort translation, so
swapping kube-proxy for Cilium changes nothing about it.

The corollary is the useful part: **an ingress gateway that does not admit
`world` on its listener port is not hardened, it is misconfigured.** It works on
the two-node topology only because the cross-node hop SNATs the source to a node
identity before the policy is evaluated.

See [`../2026-08-31-single-node-cilium-ingress-digest.md`](../2026-08-31-single-node-cilium-ingress-digest.md)
for the full investigation, including the false starts.
