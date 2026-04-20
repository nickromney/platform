# Architecture

This document explains the lab shape, not just the mechanics. The important rule is that private RFC1918 space is reused on purpose, so names and resolver viewpoint matter more than raw private addresses.

Read this after [prerequisites.md](prerequisites.md) if you want to understand what the bring-up is creating, or after [what-is-sd-wan.md](what-is-sd-wan.md) if you want to move from concept into concrete topology.

## Outcome First

The repo layout is intentional:

- outcome: `sd-wan`
- implementation: `lima`

The point of the lab is the SD-WAN behavior. Lima is only the local VM substrate used to demonstrate it.

## Request Path

```mermaid
sequenceDiagram
  participant Browser as Browser
  participant Cloud1 as cloud1 nginx
  participant WG as WireGuard
  participant Cloud2Edge as cloud2 nginx
  participant API as subnet calculator API

  Browser->>Cloud1: GET /
  Browser->>Cloud1: GET /api/v1/health
  Cloud1->>WG: mTLS request to api1.vanity.test
  WG->>Cloud2Edge: Encrypted packet to 172.16.11.2:443
  Cloud2Edge->>API: Proxy to 10.10.1.4:8000
  API-->>Cloud2Edge: JSON
  Cloud2Edge-->>Cloud1: JSON
  Cloud1-->>Browser: JSON
```

## Addressing Model

There are four different address roles in the lab, and they should not be conflated:

- cloud1 local service space: `10.10.1.0/24`
- cloud2 local service space: `10.10.1.0/24` again, on purpose
- cloud3 local service space: `172.31.1.0/24`
- cross-cloud VIP space: `172.16.10.0/24`, `172.16.11.0/24`, `172.16.12.0/24`
- WireGuard transport space: `192.168.1.0/24`
- Lima guest underlay: named `user-v2`, with each guest publishing its underlay IP into shared bring-up state

```mermaid
flowchart LR
  subgraph C1["cloud1 (Azure-style)"]
    C1A["10.10.1.4 app edge"]
    C1D["10.10.1.10 DNS"]
    C1W["192.168.1.1 wg0"]
    C1V["172.16.10.1 external VIP"]
  end

  subgraph C2["cloud2 (On-prem)"]
    C2A["10.10.1.4 API"]
    C2D["10.10.1.10 DNS"]
    C2W["192.168.1.2 wg0"]
    C2V["172.16.11.2 external VIP"]
  end

  subgraph C3["cloud3 (AWS-style)"]
    C3A["172.31.1.1 app"]
    C3D["172.31.1.10 DNS"]
    C3W["192.168.1.3 wg0"]
    C3V["172.16.12.3 external VIP"]
  end

  C1W --- C2W
  C2W --- C3W
  C1W --- C3W
```

```mermaid
flowchart TD
  Name["Service name<br/>api1.vanity.test"] --> Resolver["Resolver viewpoint<br/>which cloud are you in?"]
  Resolver --> Local1["cloud1/cloud2 local meaning<br/>10.10.1.0/24"]
  Resolver --> Local3["cloud3 local meaning<br/>172.31.1.0/24"]
  Resolver --> VIP["Cross-cloud VIP<br/>172.16.x.x"]
  VIP --> WG["WireGuard transport<br/>192.168.1.x"]
```

```mermaid
flowchart LR
  Guest1["cloud1 guest"] --> Underlay["Lima user-v2 underlay<br/>shared peer underlay IPs"]
  Guest2["cloud2 guest"] --> Underlay
  Guest3["cloud3 guest"] --> Underlay
  Underlay --> WG["WireGuard listeners<br/>inside each guest"]
```

The Lima `user-v2` underlay is only there so the guests can find one another. It is not advertised in DNS, not used as a service identity, and not part of the `172.16.x.x` cross-cloud VIP layer.

## Overlap Is The Point

cloud1 and cloud2 both reuse `10.10.1.0/24`. That means an address like `10.10.1.4` is not globally meaningful by itself.

```mermaid
flowchart LR
  subgraph cloud1["cloud1 resolver view"]
    c1dns["10.10.1.10 DNS"]
    c1app["app1.cloud1.test<br/>10.10.1.4"]
  end

  subgraph cloud2["cloud2 resolver view"]
    c2dns["10.10.1.10 DNS"]
    c2api["api1.cloud2.test<br/>10.10.1.4"]
  end

  c1dns --> c1app
  c2dns --> c2api
  c1app -. "same RFC1918 address,<br/>different workload" .- c2api
```

## Resolver Viewpoint Matters

The safe mental model is: resolve names from the cloud you are standing in, then cross clouds using the external VIP returned by that resolver.

```mermaid
sequenceDiagram
  participant C1 as client in cloud1
  participant DNS1 as cloud1 DNS
  participant WG as WireGuard mesh
  participant C2 as cloud2 API

  C1->>DNS1: resolve api1.vanity.test
  DNS1-->>C1: 172.16.11.2
  C1->>WG: connect to 172.16.11.2:443
  WG->>C2: deliver to cloud2
```

```mermaid
flowchart TD
  Start["Need cloud2 service from cloud1"] --> Good["Use cloud1 resolver"]
  Good --> VIP["api1.vanity.test -> 172.16.11.2"]
  VIP --> Reach["Reachable over WireGuard"]

  Start --> Bad["Use raw RFC1918 target"]
  Bad --> Ambiguous["10.10.1.4 is ambiguous<br/>because cloud1 and cloud2 both own it"]
```

## What To Remember

- `10.10.1.4` is local meaning, not global identity.
- the resolver you ask determines which private-world answer you get.
- cloud1 and cloud2 deliberately share one local numbering scheme, while cloud3 uses a different one.
- the `172.16.x.x` ranges are the small shared cross-cloud routable surface, not a replacement for names and resolver context.
- the Lima `user-v2` addresses are only guest-underlay plumbing for inter-VM reachability.
- cross-cloud traffic should use vanity names that resolve to `172.16.x.x` VIPs, not guessed RFC1918 addresses.
- the remote site can keep reusing its own RFC1918 space without that leaking into your routing intent.

## Workload Choice

The cloud2 API comes from `apps/subnetcalc/api-fastapi-container-app/app`. The cloud1 demo frontend is built from `apps/subnetcalc/frontend-typescript-vite`, with `apps/subnetcalc/shared-frontend` built first because the Vite frontend consumes its generated types.

Read next: [network-verification.md](network-verification.md) to see the same topology exercised with live DNS answers, WireGuard state, and end-to-end traffic.
