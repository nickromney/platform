# 2026-08-31 Single-node Cilium ingress investigation

Context: a `local-8gb` resource profile was added for constrained Docker Desktop
hosts. `worker_count = 0` looked like free memory until it produced a cluster
that was healthy by every internal measure and served nothing. This is the full
record, including the wrong turns, because the wrong turns are where the cost was.

Related: [ADR 0012](./adr/0012-hardened-cilium-ingress-assumes-cross-node-nodeport.md),
[ADR 0013](./adr/0013-resource-profiles-reduce-only.md),
[ADR 0014](./adr/0014-browser-e2e-defines-a-working-cluster.md).

## Symptom

Single-node cluster, everything green internally: one node `Ready`, no
control-plane taint, Cilium and CoreDNS running clean, all 8 dev workloads 1/1,
the `subnetcalc-dev` HTTPRoute present, Gateway `Programmed=True`. And:

| endpoint | result |
| --- | --- |
| 6443 apiserver | HTTP 200 |
| 30080 argocd | HTTP 200 |
| 30070 gateway | HTTP 000 |
| 30090 gitea | HTTP 000 |

`cilium_drop_count_total direction=INGRESS reason="Policy denied"` = 1812.

## Hypotheses that were wrong

Recording these because each looked reasonable and cost time.

1. **"argocd's policy must admit something extra."** It does not. All four
   hardened policies carry identical `fromEntities: ["host", "remote-node"]`.
   The argocd/apiserver successes were most likely an artefact of that run's
   apply failing before the policies fully synced.
2. **"`externalTrafficPolicy` differs."** All four services are `Cluster`.
3. **"Same-node NodePort traffic escapes SNAT."** Plausible, and the mechanism
   still involves identity, but kube-proxy in `Cluster` mode masquerades
   NodePort traffic regardless of hop, so this framing was not right.
4. **A first "experiment" that proved nothing.** Cordon + untaint + delete pod
   was run with all output redirected to `/dev/null`. The pod never moved -- age
   stayed 6h28m -- so the 302s observed afterwards were just the unchanged
   cross-node path. **Never redirect stderr while running an experiment whose
   whole value is knowing whether it took effect.**

## What the evidence actually established

Cilium reserved identities on this cluster: `1 = reserved:host`,
`2 = reserved:world`, `6 = reserved:remote-node`.

- The gateway endpoint's live policy admits `reserved:host`,
  `reserved:remote-node`, `reserved:aggregate-remote-node`. **No `world`.**
- `172.18.0.1` (the Docker bridge gateway) is **absent from the ipcache**, so it
  falls to `0.0.0.0/0 -> identity=2` = `world`.
- The control-plane taint puts all 49 workload pods on the worker while the
  `extraPortMappings` are on the control-plane, so every request crosses a node
  boundary and resolves to an admitted node identity.
- `worker_count = 0` must remove that taint or nothing schedules, so workloads
  land on the port-mapped node.

## The controlled reproduction

Run on a **two-node** cluster, changing only pod placement:

| gateway pod placement | `subnetcalc.dev` |
| --- | --- |
| worker (cross-node) | HTTP 302 |
| control-plane (co-located with port mappings) | HTTP 000 |
| moved back to worker | HTTP 302 |

```text
xx drop (Policy denied) ... identity world->1085: 10.244.0.97 -> 10.244.0.42:443 tcp SYN
```

So **node count was never the variable. Co-location was.**

## Cilium kube-proxy replacement: fixes the denial, not the whole path

Added `cilium_kube_proxy_replacement` (default `false`), which sets kind's
`kubeProxyMode: "none"` and Cilium's `kubeProxyReplacement: true` plus
`k8sServiceHost`/`k8sServicePort` -- Cilium cannot reach the apiserver through a
Service once kube-proxy is gone. Both kind config paths (the inline
`kind_cluster` block and `kind-config.yaml.tpl`) must move together.

On a single-node cluster with it enabled:

- `KubeProxyReplacement: True [eth0 172.18.0.2 (Direct Routing)]`
- kube-proxy DaemonSet does not exist
- Cilium programs the NodePorts: `0.0.0.0:30070 -> 10.244.0.91:443 (active)`
- **the policy denial is NOT gone.** An early monitor run recorded nothing and
  was misread as success; capturing for longer shows the same denial, from the
  host (`172.18.0.1`) and from a sibling container (`172.18.0.3`), both `world`
- From inside the node the whole path works: `172.18.0.2:30070` returns 404
  without a `Host` header, and **302 with `Host: subnetcalc.dev.127.0.0.1.sslip.io`**
- From inside the node, loopback works too: `127.0.0.1:30070` returns 404

But from the host, still HTTP 000, with the port mapping present
(`30070/tcp -> 127.0.0.1:443`) and `com.docker.backend` listening on 443.

**Conclusion: kube-proxy replacement does not solve the identity problem.**
Cilium's NodePort translation is correct; the packet reaches the gateway endpoint
and is denied there because its source is `world`. The identity follows the
source address, so it makes no difference whether kube-proxy or Cilium performs
the translation. A sibling container on the kind network reproduces it without
Docker's port-forward involved at all, which rules the forward out as a cause.

The real defect is in the policy: **the platform gateway does not admit `world`
on its listener port**, and only works on two nodes because the cross-node hop
SNATs the source to a node identity first.

## The fix, and what it did and did not solve

The policies were changed to match their own stated intent -- `world` admitted on
the gateway's :443 and on gitea's published NodePorts, nothing wider. Results:

- `gitea :30090` from the host on a **single node**: HTTP 000 -> **200**
- no policy drops recorded for any request, on either topology
- **two-node** stage-900 apply with the fix: `exit=0`, `subnetcalc.dev` still 302

So the identity problem is solved and the fix is topology-independent, which was
the requirement.

Single-node is still not serviceable, for a **different** reason. The gateway's
TLS handshake over the host 443 mapping resets:

```text
curl:  Connected to 127.0.0.1 port 443 -> TLS Client hello -> Recv failure: Connection reset by peer
nginx: client closed connection while SSL handshaking, client: 10.244.0.69
```

The connection reaches nginx and the handshake begins. Plain HTTP on gitea's
NodePort succeeds on the same cluster, so it is specific to the TLS flight.
eth0 inside the kind node has **MTU 65535** and the Cilium interfaces 65520
(Docker Desktop's jumbo virtual networking), so the leading hypothesis is that the
large certificate flight does not survive the path to the host while small packets
do. **Untested.** Pinning Cilium's MTU to 1500 is the obvious first experiment.

## A process lesson that cost real time

`kubectl apply` of a fixed CiliumClusterwideNetworkPolicy was **silently reverted
by Argo self-heal** within seconds -- `selfHeal=true`, synced from the in-cluster
Gitea repo, not the working tree. The endpoint kept showing the old policy and the
fix looked like it had failed. Policy changes only count once they go through
`make -C kubernetes/kind gitea-sync AUTO_APPROVE=1`, or a full rebuild.

## If picking this up again

- The remaining question is narrow and is **not** about identity or the port
  forward, both of which are now understood: why does the TLS handshake reset over
  the host 443 mapping when plain HTTP on another NodePort succeeds?
- Test MTU first. Pin Cilium's MTU to 1500 and retry; the 65535/65520 mismatch
  against the host path is the leading explanation.
- Cilium Gateway API in host-network mode may make this moot by removing the
  NodePort hop entirely. See
  [cilium-ingress-next-steps](./plans/cilium-ingress-next-steps.md).
- Hubble is the right tool and `local-8gb` disables it. Enable
  `enable_hubble = true` for the debug run.
- Do not chase this for memory. Single-node measured ~117 Mi of actual saving;
  the 24 removed pods did the real work.
