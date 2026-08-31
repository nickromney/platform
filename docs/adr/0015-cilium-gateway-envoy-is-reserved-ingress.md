# ADR 0015: Cilium's Gateway Envoy reaches backends as reserved:ingress

- Status: Accepted
- Recorded: 2026-08-31

## Context

Moving the platform ingress from NGINX Gateway Fabric to Cilium's Gateway API
implementation changes what the hardened `CiliumClusterwideNetworkPolicy` set is
actually looking at, in two ways that are easy to miss because nothing fails
loudly at render time.

**There are no gateway pods.** NGF runs a data-plane pod per Gateway in the
`platform-gateway` namespace. Cilium terminates Gateway API traffic in the Envoy
embedded in its own `cilium-agent` DaemonSet, in host-network mode on kind. A
bare `gatewayClassName: cilium` Gateway produced a `cilium-gateway-<name>`
NodePort Service with a real ClusterIP, a `CiliumEnvoyConfig`, and no pods at
all.

`platform-gateway-hardened` selects on
`"k8s:io.kubernetes.pod.namespace": platform-gateway`. With no pods in that
namespace the policy selects nothing and stops applying. It still reads, in the
tree and in `kubectl get ccnp`, as though it is protecting the ingress path.

**The Envoy does not present the host identity.** That is the natural guess for
a host-network listener, and it is wrong. A Cilium Gateway in the real
`platform-gateway` namespace, pointed at the real `oauth2-proxy-argocd`, through
the unmodified hardened policies, returned 503. `cilium-dbg monitor --type drop`
on the node hosting the **backend** gave the reason:

```text
xx drop (Policy denied) ... identity ingress->48344: 10.244.0.166 -> 10.244.1.224:4180 tcp SYN
```

The identity is `reserved:ingress`.

The first capture was taken on the *gateway's* node, recorded nothing, and
looked like proof that no policy was involved. Drops are recorded where the
packet is dropped, which is the destination endpoint's node.

## Decision

Ship a `cilium-gateway-ingress` policy set, rendered only when
`cilium_gateway_api` is enabled, that admits `fromEntities: [ingress]` on each
backend the gateway serves.

The allowance is expressed as **ingress on the backends**, not as egress from the
gateway, because there is no gateway endpoint to attach egress to. Each document
mirrors one egress allowance that `platform-gateway-hardened` grants the NGINX
gateway pods, scoped to the same namespace and app labels.

A single `endpointSelector: {}` would have been one rule instead of ten. It is
rejected: it would open those ports to `reserved:ingress` on every endpoint in
the cluster, which defeats the point of a hardened set. The `nginx-gateway`
control-plane allowance is deliberately absent, because it does not exist in this
mode.

The policies are pruned on the NGINX path rather than shipped inert, since
`reserved:ingress` describes nothing there. `check-policy-drift.sh` is taught to
skip them by name when the mode is off, and to report how many it skipped --
otherwise it correctly reports ten policies missing from a cluster that is
behaving exactly as designed.

## Consequences

Verified end to end: the same probe, against the same hardened policies, went
from 503 to 302, with 302 being the correct oauth2-proxy redirect to Keycloak.

`platform-gateway-hardened` becoming inert is not addressed by this ADR. In
Cilium mode it is dead weight that still looks protective. It should either be
rewritten against the Envoy's identity or pruned in that mode; leaving it as-is
invites someone to read it as the ingress control it no longer is.

This is the second time on this stack that a policy has appeared to work for a
reason other than the stated one -- ADR 0012 records the first. Both were found
by watching drops rather than by reading the policy. Treat "the policy admits X,
therefore traffic from X arrives as X" as a hypothesis to test, and test it on
the node that owns the destination.
