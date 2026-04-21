# SD-WAN Analysis

This is a DDD pass over `sd-wan/lima`.

`sd-wan` is the second top-level solution in this repo alongside `kubernetes`.
Its variant today is `lima`, which demonstrates the SD-WAN behavior on three
macOS-hosted VMs.

The solution/variant taxonomy is the same as in the kubernetes stacks:

- `solution` is `sd-wan`
- `variant` is `lima`

This doc intentionally avoids repeating the mechanics that already live in
[`sd-wan/lima/docs/architecture.md`](../../sd-wan/lima/docs/architecture.md).
It focuses on the domain model the lab is teaching.

## Domain Core Versus Supporting Concerns

The domain core is:

- reuse private RFC1918 space on purpose across sites
- keep resolver viewpoint as a first-class modeling concern
- expose stable cross-cloud identity through vanity names and a small VIP space
- separate transport identity from service identity

Supporting concerns are:

- Lima VM lifecycle (`user-v2` underlay, guest bring-up)
- WireGuard transport (keys, peers, endpoints, allowed-IPs)
- mTLS ingress and CA trust
- nginx edge terminations on each cloud
- split-brain DNS (per-cloud resolver)
- the embedded `subnetcalc` workload on cloud2

The supporting stack is substantial, but the business claim is compact: raw
private IPs are not trustworthy cross-cloud identifiers.

## Observed User Capabilities

From the lab scripts, cloud APIs, and tests the current capabilities are:

- bring the three-cloud mesh up, down, or destroy it as one unit
- look at one cloud's view of another cloud's service through a vanity name
- query the cloud-local resolver and see the answer that viewpoint produces
- inspect WireGuard peer state and traceroute across the overlay
- run the `subnetcalc` frontend on cloud1 against the cloud2 backend through
  a WireGuard-plus-mTLS path

## Candidate Domain Model

Candidate value objects:

- `CloudSite` — the named site (`cloud1`, `cloud2`, `cloud3`)
- `ResolverViewpoint` — whose DNS you are asking
- `VanityName` — the stable cross-cloud service name (e.g. `api1.vanity.test`)
- `ServiceVIP` — the `172.16.x.x` cross-cloud routable surface
- `LocalServiceAddress` — the RFC1918 address that only makes sense in-site
- `UnderlayAddress` — Lima `user-v2` guest reachability, not a service identity
- `OverlayPeer` — a WireGuard peer with public key, endpoint, allowed-IPs
- `MeshHandshake` — latest-handshake state per peer

Candidate domain services:

- `NameResolutionService` — answers a query from a chosen viewpoint
- `OverlayReachability` — whether a peer is currently established
- `CrossCloudCaller` — a site-to-site request that uses a vanity name and
  terminates through mTLS

Candidate supporting contexts inside the lab:

- `LabLifecycle` — bring up / down / destroy, guest provisioning, hostname wiring
- `TrustAnchor` — root-CA distribution, client cert issuance
- `NetworkInspection` — DNS raw, traceroute, tunnel-state reporting

## Rules Already Visible In The Lab

- `cloud1` and `cloud2` deliberately reuse `10.10.1.0/24`; `cloud3` uses
  `172.31.1.0/24`.
- Cross-cloud VIPs live in `172.16.10.0/24`, `172.16.11.0/24`, and
  `172.16.12.0/24`.
- WireGuard transport space is `192.168.1.0/24` and is not a service identity.
- Lima `user-v2` underlay addresses exist only so guests can find each other.
- A vanity name resolves to a VIP from any viewpoint; a raw `10.10.1.4` target
  is ambiguous across sites.
- mTLS client identity is expressed through `X-Client-CN` and `X-Client-Verify`
  headers at the nginx edges, and through `X-Ingress-Cloud` and `X-Egress-Cloud`
  for route attribution.

## Relationship To `subnetcalc`

The `subnetcalc` container-app is the cloud2 workload. From the SD-WAN point
of view, `subnetcalc` is a black-box HTTP service reached by vanity name. The
lab does not try to change or specialize the `subnetcalc` domain model.

In DDD terms: **the sd-wan context is a Conformist to the `subnetcalc`
published API.** It does not negotiate the backend shape, and it does not
introduce an Anticorruption Layer between itself and `subnetcalc`. The vanity
name and the mTLS edge are the boundary; the payload below that boundary is
whatever `subnetcalc` publishes.

A second touch point exists today: the `subnetcalc` container-app also owns
`/api/v1/network/diagnostics`, whose payload shape overlaps with the cloud
guests' `/network/diagnostics` endpoint in `sd-wan/lima/api/main.py`. Those
two endpoints are related but not a shared kernel yet — they are parallel
readings of the same underlying overlay from different positions.

## What Looks Stable

- the four address roles (`local`, `cross-cloud VIP`, `overlay transport`,
  `guest underlay`)
- resolver viewpoint as the primary correctness concern
- vanity names as the stable identity contract
- mTLS as the boundary for cross-cloud trust
- Lima as the variant label, not as the domain

## What Looks Incidental

- the specific subnet numbers used in the lab
- the exact `nginx` terminations
- the fact that the lab ships a small sd-wan-specific FastAPI alongside
  `subnetcalc` — this is a visualisation aid, not a business capability
- the inspector UI under `sd-wan/lima/html/inspector`

## Vocabulary Collisions To Watch

- `cloud` — means a named lab site here, not a hyperscaler
- `proxy` — already overloaded in the kubernetes stacks; in sd-wan it usually
  means the nginx edge or the `/proxy/{system}` helper on the cloud API
- `network` — `subnetcalc` uses this as a CIDR block under analysis; sd-wan
  uses it for the overlay and for diagnostics

These collisions do not require pre-launch renames. They are worth recording so
the ubiquitous language can disambiguate them later.

## Best Next Red Tests In Domain Language

- "A vanity name resolves to a VIP from any cloud's resolver viewpoint"
- "The same RFC1918 address means different workloads in cloud1 and cloud2"
- "A cross-cloud call terminates with a recognized client CN at the far edge"
- "Overlay reachability is independent of the Lima guest underlay"
- "cloud2 serves `subnetcalc` without altering the `subnetcalc` API shape"

## DDD Read

`sd-wan/lima` is a small but coherent bounded context. Its domain language is
already sharper than the Kubernetes stack-operations language because the lab
was built around a single teaching claim.

The best pre-launch move is to leave the implementation alone and keep this
doc as the single place that names the domain. Post-launch, the strongest
refactor candidate is extracting `/network/diagnostics` into a shared payload
that both `subnetcalc` and the sd-wan cloud API can produce, with the
difference being the viewpoint rather than the shape.
