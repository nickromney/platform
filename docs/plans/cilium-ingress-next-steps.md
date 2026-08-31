# Next steps: Cilium Gateway API as the platform ingress

Status: investigation complete, not started.
Written: 2026-08-31, for a session picking this up cold.

## Why this is on the table

The platform's L7 ingress is NGINX Gateway Fabric. Cilium can implement Gateway
API itself through its L7 (Envoy) proxy, which would remove a component and pull
ingress earlier in the stack. The prompt for looking at it was a memory pass, but
**footprint is not the reason to do this**: `nginx-gateway` (42 Mi) plus
`platform-gateway-nginx` (67 Mi) is ~110 Mi, about 2% of a 4.66 GiB cluster, and
Cilium's Envoy grows to absorb the work. The case is architectural.

Source of truth for the requirements:
<https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/>

## Prerequisites, and where this repo stands

| requirement | repo status |
| --- | --- |
| `kubeProxyReplacement=true` | **wired, defaulted off**: `var.cilium_kube_proxy_replacement` sets kind's `kubeProxyMode: "none"` and Cilium's `kubeProxyReplacement` + `k8sServiceHost`/`k8sServicePort` together. Verified to build: `KubeProxyReplacement: True [eth0 ... Direct Routing]`, kube-proxy DaemonSet absent, NodePorts programmed by Cilium. |
| `l7Proxy=true` | default-on upstream; not currently set explicitly in `local.cilium_values`. |
| Gateway API CRDs | already installed (`nginx-gateway-fabric-crds`), experimental channel v1.4.1. |
| Cilium version | **1.20.1** -- comfortably above the 1.16 needed for host-network mode. |
| LoadBalancer service | **not available.** kind has no LB provider; the one `LoadBalancer` service in the cluster (`agentgateway-ai-gateway`) has sat `<pending>` indefinitely. |

## The two findings that shape the plan

**1. Host-network mode is not optional here, it is the whole approach.**
Cilium's Gateway API controller creates a `LoadBalancer` service by default. That
cannot work on kind. Since 1.16 the L7 proxy can be exposed directly on the host
network instead, which is the only viable path on this stack -- and is likely
*better* than the current arrangement, because kind's `extraPortMappings` would
reach the proxy directly on the node's host network rather than through a
NodePort DNAT into a pod.

That may also sidestep two problems this repo has already hit:

- the `reserved:world` identity denial documented in
  [ADR 0012](../adr/0012-hardened-cilium-ingress-assumes-cross-node-nodeport.md),
  because traffic would arrive on the host network rather than being DNAT'd to a
  pod endpoint where policy is evaluated
- the unresolved single-node TLS handshake failure, which is suspected to be an
  MTU problem on the NodePort path (eth0 MTU 65535 inside the kind node)

Neither is proven. Both are worth testing early, because if host-network mode
resolves them it strengthens the case considerably.

**2. This does not have to be a big-bang migration.**
The cluster already runs **two** Gateway API implementations side by side:

```text
agentgateway-system/agentgateway-ai-gateway   class=agentgateway   80/HTTP    1 HTTPRoute
platform-gateway/platform-gateway             class=nginx          443/HTTPS  16 HTTPRoutes
```

So adding a third `GatewayClass` is a pattern the repo already demonstrates.
Routes bind by `parentRefs`, which means they can be moved **one at a time**, and
moved back.

## Exact chart values (cilium 1.20.1, read from `helm show values`)

```yaml
gatewayAPI:
  enabled: true          # default false
  gatewayClass:
    create: auto         # creates the `cilium` GatewayClass
  secretsNamespace:
    create: true
    name: cilium-secrets
    sync: true           # TLS secrets are synced here, see the TLS note below
  hostNetwork:
    enabled: true        # REQUIRED on kind: no LoadBalancer provider
    nodes:
      matchLabels: {}    # pin to the node holding the kind extraPortMappings
```

The chart's own commented example for `hostNetwork.nodes.matchLabels` is
`kubernetes.io/hostname: kind-worker`, which is a good sign this path is
exercised on kind upstream.

`kubeProxyReplacement: true` is already wired behind
`var.cilium_kube_proxy_replacement`. `l7Proxy` is on by default and needs no
change.

## The port-mapping trap

This one will waste an afternoon if it is not planned for. Today the gateway is a
**NodePort**, and kind maps **containerPort 30070 to hostPort 443**:

```yaml
extraPortMappings:
  - containerPort: 30070
    hostPort: 443
```

With `gatewayAPI.hostNetwork.enabled=true` the Envoy listener binds the Gateway's
own port directly on the node's host network -- **443**, not 30070. The existing
mapping would point at nothing. The kind config needs a `containerPort: 443`
mapping for the Cilium path, and kind bakes port mappings at cluster creation, so
this cannot be changed on a live cluster.

Both mappings can coexist during migration (different container ports), which is
what makes the incremental `parentRefs` approach viable.

Also note `hostNetwork.nodes.matchLabels` must select **the node that holds the
port mappings**. In this repo that is the control-plane, which carries a
`NoSchedule` taint -- fine, because Envoy runs in the cilium agent/cilium-envoy
DaemonSets which tolerate it, but it is the opposite of where workloads land.

## What a first build actually produced (2026-08-31, two-node)

Built with `cilium_kube_proxy_replacement = true`, `cilium_gateway_api = true`
and the host-network node selector pinned to the control plane. Results:

Working as designed:

- kind created **both** port mappings -- `30070/tcp -> 443` (NGINX) and
  `443/tcp -> 8443` (Cilium host-network listener). The parallel-migration model
  holds.
- kube-proxy DaemonSet absent; `kube-proxy-replacement = true`.
- A **`cilium` GatewayClass appears** (`io.cilium/gateway-controller`) alongside
  `nginx` and `agentgateway`.
- `cilium-config` carries what was intended:
  `enable-gateway-api=true`, `enable-l7-proxy=true`,
  `gateway-api-hostnetwork-enabled=true`, and
  `gateway-api-hostnetwork-nodelabelselector=kubernetes.io/hostname=kind-local-control-plane`.
- The operator confirms host networking is live:
  *"Gateway API host networking is enabled, externalTrafficPolicy will be ignored."*
- **The existing NGINX path is unaffected**: `subnetcalc.dev` still returns 302
  with kube-proxy replacement and Gateway API both on.

### It is safe: the whole stack still passes

With `kubeProxyReplacement` and `gatewayAPI` both enabled on two nodes, stage 900
applied `exit=0` and the platform is fully functional:

- `check-gateway-urls`: **60 OK / 0 FAIL**
- `check-sso-e2e`: **exit 0, 13 passed / 0 failed**, including both cross-app
  sign-out tests
- memory 6.15 GiB of the 8.72 GiB limit, against a 5.60 GiB baseline -- so the
  Cilium stack costs about **+0.55 GiB**, mostly cilium-envoy

That is the reassuring half: turning this on does not destabilise anything, so
the migration can proceed incrementally without holding the platform hostage.

### The cost: kube-proxy replacement makes apply 12.5x slower at one step

| build | `recover_kind_cluster_after_oidc_restart` |
| --- | --- |
| two-node, no KPR | **2m49s** |
| two-node, **with KPR** | **35m08s** |
| single-node, no KPR | 2m46s |

Total stage-900 apply went from 12.5 min to **59.1 min**, and essentially all of
the difference is that one step. It is clearly attributable to kube-proxy
replacement rather than topology, since single-node without KPR matches the
baseline.

The likely mechanism: the apiserver restarts for OIDC reconfiguration, and with
kube-proxy gone Cilium must re-reach it via `k8sServiceHost` before the
`kubernetes` Service is programmed again. Anything needing the API stalls until
Cilium recovers, presumably behind a retry backoff.

This matters more than it looks. Kube-proxy replacement is a **hard prerequisite**
for Cilium Gateway API, so this cost is not optional -- it is the price of
entry, paid on every apply. Worth investigating before committing:

- does `k8sServiceHost` pointing at the container name (rather than an IP) slow
  re-resolution after the restart?
- would ordering OIDC reconfiguration before Cilium, or reversing the restart
  order, avoid the stall entirely?
- is the recovery loop's backoff simply too coarse for a restart that actually
  completes in seconds?

### The blocker: Gateway API CRD versions

The GatewayClass sits at `Accepted=Unknown`, `reason=Pending`,
`"Waiting for controller"`, and the operator says why:

```text
Required GatewayAPI resources are not found
CRD "tlsroutes.gateway.networking.k8s.io" does not have version "v1"
CRD "referencegrants.gateway.networking.k8s.io" does not have version "v1"
```

Cilium 1.20's controller requires **v1** for the full required set. The bundle
this repo installs for NGINX Gateway Fabric
(`apps/nginx-gateway-fabric-crds`, Gateway API **v1.4.1, experimental channel**)
serves:

| CRD | installed | Cilium 1.20 needs |
| --- | --- | --- |
| httproutes | v1, v1beta1 | v1 -- ok |
| grpcroutes | v1 | v1 -- ok |
| backendtlspolicies | v1, v1alpha3 | v1 -- ok |
| **tlsroutes** | **v1alpha2, v1alpha3** | **v1 -- missing** |
| **referencegrants** | **v1beta1** | **v1 -- missing** |

So the controller never claims the class and no Gateway can be programmed. This
is the first thing to solve, and it is a **shared-CRD** problem: NGINX Gateway
Fabric and Cilium both consume the same cluster-scoped bundle, so the version
has to satisfy both at once. Options, in the order worth trying:

1. Find a Gateway API bundle version whose `tlsroutes` and `referencegrants`
   are served at v1 and which NGINX Gateway Fabric 2.5.1 still accepts. Check
   Cilium's own documented Gateway API version requirement for 1.20 first --
   it pins a specific release.
2. Let Cilium install and own the Gateway API CRDs, and check whether NGF
   tolerates that bundle. Riskier, because ownership of a cluster-scoped
   resource then moves.
3. If no single bundle satisfies both, the parallel-migration plan does not
   work and this becomes a cutover, which changes the risk calculus entirely.

Note `referencegrants` at v1beta1 is also what the repo's own manifests pin
(`ReferenceGrant apiVersion pinned to gateway.networking.k8s.io/v1beta1` is
asserted by `check-component-version.sh`), so moving it is not just a CRD swap.

## RESOLVED (2026-08-31): the CRD blocker, and a validated data path

The blocker above is fixed, and the Cilium data path is proven. Both were
verified on the live two-node cluster rather than reasoned about.

### Root cause, in the operator's own words

`cilium-operator` runs its Gateway API preflight exactly once, at startup, in
`gateway-api.initGatewayAPIController`. On the v1.4.1 bundle it logged:

```
Required GatewayAPI resources are not found, please refer to docs for installation instructions
  CRD "tlsroutes.gateway.networking.k8s.io" does not have version "v1"
  CRD "referencegrants.gateway.networking.k8s.io" does not have version "v1"
```

Cilium 1.20 requires those two at `v1`. No Gateway API release at or below
v1.4.1 serves them there. v1.5.1 and v1.6.1 both do, and both keep the legacy
versions served alongside, so existing pinned manifests keep working.

`apps/nginx-gateway-fabric-crds/gateway-api-crds.yaml` is now the **v1.6.1
experimental** bundle (20825 -> 24120 lines, 13 CRDs). After applying it and
restarting the operator, the served versions are `tlsroutes: v1 v1alpha2
v1alpha3` and `referencegrants: v1 v1beta1`, and:

```
NAME           CONTROLLER                                   ACCEPTED
cilium         io.cilium/gateway-controller                 True
```

Because the preflight is startup-only, **the operator must be restarted after
the CRDs land** or the GatewayClass stays `Accepted=Unknown / Waiting for
controller` indefinitely. That is a real upgrade-ordering hazard, not a
one-off.

### The data path works, end to end

A throwaway Gateway (`gatewayClassName: cilium`, HTTP listener, HTTPRoute to an
agnhost backend) reached `Accepted=True` / `Programmed=True`, Cilium created a
`CiliumEnvoyConfig`, and traffic flowed:

```
HTTP/1.1 200 OK
server: envoy
probe-677cfcd9fd-pdc8j
```

Envoy bound on the control-plane node; the backend pod was on the worker. So
this is genuine cross-node L7 proxying through Cilium's Envoy, not a
same-node shortcut. Cilium Gateway API is viable here.

Note the host-network listener bound on the control plane only. That is what we
want -- it is the node carrying kind's `extraPortMappings` -- but it is
incidental rather than enforced, so pin it with
`cilium_gateway_api_host_network_node_labels` rather than relying on it.

### What the cutover still costs

The platform-gateway app is six-sevenths NGF-coupled. Only `namespace.yaml`
survives untouched; `gateway.yaml` is rewritten and these five are deleted:

| Resource | Why it cannot survive |
| --- | --- |
| `nginxproxy.yaml` | `gateway.nginx.org` NginxProxy, referenced by `infrastructure.parametersRef` |
| `tls-hardening.yaml` | `gateway.nginx.org/v1alpha1` SnippetsPolicy |
| `proxysettingspolicy-oauth-response-buffers.yaml` | NGF ProxySettingsPolicy |
| `gateway-service.yaml` | NodePort `platform-gateway-nginx`; host-network Envoy needs no Service |
| `agent-tls-bootstrap.yaml` | RBAC bootstrapping `platform-gateway-nginx-agent-tls` for the NGINX agent |

`render_platform_gateway_for_cilium` in `sync-gitea-policies.sh` now performs
exactly that swap, gated on `cilium_gateway_api`, and prunes the NGF Argo
application so the two implementations cannot fight over one Gateway.

**Two capability losses are real and unmitigated.** The SnippetsPolicy TLS
hardening (ssl-protocols, prefer-server-ciphers) and the OAuth response-buffer
tuning have no Cilium equivalent in this shape. Whoever finishes the cutover
must either reproduce them through `CiliumGatewayClassConfig`/Envoy settings or
consciously accept weaker TLS settings than the NGF path enforces today.

Beyond the app itself, roughly 25 files still reference the NGF identity --
`check-gateway-urls.sh`, `check-gateway-stack.sh`, `check-cluster-health.sh`,
`gateway-bootstrap.tf`, the `nginx-gateway-hardened` and
`azure-auth-nginx-gateway-ingress` Cilium policies, the subnetcalc canary patch,
`tests/app_contracts.py`, and several bats suites. The hardened-policy files
matter most: they select the NGF pods by label, and a host-network Envoy
presents the **host** identity instead, which those policies already admit. That
is likely to make the ingress path simpler than it is today, but it must be
proven with `cilium-dbg monitor --type drop`, not assumed -- assuming it is the
exact mistake recorded in ADR 0012.

### What Cilium provisions, measured

A bare `gatewayClassName: cilium` Gateway on port 8082 produced:

```
NAME                TYPE       CLUSTER-IP     PORT(S)
cilium-gateway-p2   NodePort   10.96.164.35   8082:31525/TCP

Pods: none
Gateway addresses: 172.18.0.2, 172.18.0.3
```

Three things follow, and they change the shape of the remaining work:

1. **There are no gateway pods.** Envoy runs inside the `cilium-agent`
   DaemonSet. Anything selecting the NGF pods by label -- most importantly the
   hardened Cilium policies -- has no pod to select and must be rewritten
   against the host identity instead.
2. **In-cluster access survives, but moves.** Cilium creates
   `cilium-gateway-<gateway-name>` with a real ClusterIP. So
   `kubernetes_service_v1.platform_gateway_nginx_internal` in
   `gateway-bootstrap.tf` -- a ClusterIP selecting four NGF labels, used by the
   SSO path -- does not need an Endpoints hack. It should either be repointed at
   `cilium-gateway-platform-gateway` or dropped in favour of it.
3. **Both nodes are advertised.** The Gateway reports every host-network node as
   an address, so the `extraPortMappings` node is not privileged by Cilium. Pin
   the binding with `cilium_gateway_api_host_network_node_labels` rather than
   relying on which node happens to answer.

`platform-gateway-tls` is unaffected: it is issued by cert-manager, and neither
the Certificate nor `wait-for-platform-gateway-tls.sh` knows anything about NGF.

## Suggested sequence

1. **Prove host-network mode in isolation.** Enable
   `cilium_kube_proxy_replacement = true`, add `gatewayAPI.enabled=true` and the
   host-network settings to `local.cilium_values`, and confirm a `cilium`
   GatewayClass appears alongside the existing two. Change no routes yet.
2. **Stand up a parallel Gateway** on the Cilium class, on a different port, and
   point **one** low-risk HTTPRoute at it. `subnetcalc-dev` is a good candidate:
   it is covered by the browser E2E, so success and failure are both loud.
3. **Check the identity question early.** With one route live, confirm from the
   host and from a sibling container on the kind network whether traffic still
   presents as `reserved:world` at the policy layer. If host-network mode changes
   this, ADR 0012's constraint may relax and single-node becomes viable.
4. **Migrate routes in batches**, re-running `check-gateway-urls` (57 assertions,
   seconds) between each. Keep nginx-gateway serving whatever has not moved.
5. **Only then** consider removing NGINX Gateway Fabric, its CRDs and its
   hardened policies.

## Things that will bite

- **TLS.** cert-manager issues `platform-gateway-tls` and 16 hostnames are
  asserted by `check-gateway-urls`. Cilium's Gateway wants the same secret
  reference; verify the ReferenceGrants carry over.
- **oauth2-proxy.** Every protected route redirects through oauth2-proxy to
  Keycloak. The 12-test browser E2E exercises the full flow including two
  cross-app sign-out tests. Do not declare success on a `302` alone -- run
  `check-sso-e2e`.
- **The hardened Cilium policies** reference `platform-gateway` by namespace in
  both ingress and egress rules. A Cilium-hosted gateway on the host network sits
  somewhere else in the policy model; expect to rewrite
  `platform-gateway-hardened` rather than port it.
- **`kubeProxyReplacement` forces a cluster recreate** -- kind bakes
  `kubeProxyMode` at creation. Every iteration is a full reset plus stage 100 and
  900, roughly 15-25 minutes.
- **Argo self-heal will revert live edits.** Policy and manifest changes must go
  through `make -C kubernetes/kind gitea-sync AUTO_APPROVE=1`; a `kubectl apply`
  is silently undone within seconds.

## How to verify, in order

Anything earlier than the last line is necessary but not sufficient -- see
[ADR 0014](../adr/0014-browser-e2e-defines-a-working-cluster.md).

```bash
make -C kubernetes/kind 900 apply AUTO_APPROVE=1      # must exit 0
make -C kubernetes/kind check-gateway-urls            # 57 OK / 0 FAIL
make -C kubernetes/kind check-sso-e2e                 # 12 passed / 0 failed
```

## Recommendation

Worth doing, but as its own piece of work with a cluster to burn, not folded into
another change. The incremental `parentRefs` path makes it far less risky than it
first looks, and host-network mode is the detail that makes it possible on kind
at all.
