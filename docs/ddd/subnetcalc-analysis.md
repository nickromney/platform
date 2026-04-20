# Subnetcalc Analysis

This is a deeper DDD pass over `subnetcalc`.

The current implementation is spread across multiple frontend and backend
shapes, but the domain core is much narrower than the hosting matrix.

## Domain Core Versus Supporting Concerns

The domain core is the network-analysis model:

- validate an address or network
- classify an IPv4 address as RFC1918, RFC6598, or neither
- check whether an address or network overlaps Cloudflare ranges
- calculate subnet facts under a chosen cloud mode

Supporting concerns are:

- authentication mode selection
- frontend framework choice
- hosting variant choice
- API mediation through the APIM simulator
- transport-specific headers and token handling

That split is already visible in the code:

- the core calculation rules sit in [subnets.py](../../apps/subnetcalc/api-fastapi-container-app/app/routers/subnets.py)
- the auth boundary sits in [auth_utils.py](../../apps/subnetcalc/api-fastapi-container-app/app/auth_utils.py)
- the frontend orchestration sits in [client.ts](../../apps/subnetcalc/frontend-react/src/api/client.ts)
- the APIM simulator has its own contract and policy language in
  [contract_matrix.yml](../../apps/subnetcalc/apim-simulator/contracts/contract_matrix.yml)

## Observed User Capabilities

From the API routes and frontend client, the current user-facing capabilities
are:

- validate a string as an IPv4 address, IPv6 address, or CIDR network
- classify IPv4 addresses as private or shared-address-space
- check Cloudflare membership for IPv4, IPv6, and networks
- calculate subnet details for a network
- run a combined lookup that orchestrates the previous capabilities and records
  timing

That combined lookup is important: it is the main user interaction shape in the
frontend, but it is not yet clearly modeled as a domain concept on the backend.

## Candidate Domain Model

Candidate value objects:

- `Address`
- `Network`
- `AddressVersion`
- `CloudMode`
- `SubnetInfo`
- `PrivateRangeMatch`
- `CloudflareMembership`

Candidate domain services:

- `AddressValidator`
- `AddressClassifier`
- `SubnetCalculator`
- `CloudRangeMatcher`

Candidate application service:

- `LookupService`
  This would orchestrate validation, private-range classification,
  Cloudflare membership, and subnet calculation without making the orchestration
  itself part of the low-level transport code.

## Rules Already Captured In Tests

The current tests already describe real domain rules:

- IPv4 and IPv6 validation are both supported.
- CIDR input is treated as a network rather than a single address.
- RFC1918 and RFC6598 are distinct classifications.
- IPv6 is rejected for the RFC1918 check.
- Cloudflare membership works for IPv4, IPv6, and network inputs.
- `Azure` and `AWS` reserve five IPv4 addresses in ordinary subnets.
- `OCI` reserves three IPv4 addresses in ordinary subnets.
- `Standard` reserves two IPv4 addresses in ordinary subnets.
- `/31` is treated as an RFC 3021 point-to-point case.
- `/32` is treated as a single-host case.
- IPv6 subnet calculation is a separate path and does not reuse the IPv4
  reservation rules.

Those rules are visible in
[test_subnets.py](../../apps/subnetcalc/api-fastapi-container-app/tests/test_subnets.py).

## Auth Is A Boundary, Not The Core Model

`subnetcalc` currently supports several auth methods:

- none
- API key
- JWT
- Azure SWA
- APIM

That is important delivery behavior, but it is not the domain core. The current
`get_current_user` dependency translates transport-specific identity into a
simple caller identity string. That is the correct direction: keep header,
token, and platform details out of subnet rules.

The current auth surface is visible in
[auth_utils.py](../../apps/subnetcalc/api-fastapi-container-app/app/auth_utils.py)
and [test_auth.py](../../apps/subnetcalc/api-fastapi-container-app/tests/test_auth.py).

## APIM Is A Separate Supporting Context

The APIM simulator is not just a helper library. It has its own language:

- route host matching
- version routing
- subscription enforcement
- policy execution
- management-plane projections

That means APIM should be treated as a separate supporting context, not folded
into the subnet domain model. `subnetcalc` depends on it in some paths, but is
not defined by it.

## What Looks Stable

- address and network validation
- cloud-mode-specific reservation rules
- RFC1918 versus RFC6598 distinction
- IPv4/IPv6 split
- subnet info as a coherent result object

## What Looks Unstable Or Overloaded

- whether `lookup` is a domain concept or only a UI composition
- the degree to which APIM policy and auth headers leak into app language
- the mixing of hosting and variant vocabulary with domain vocabulary
  throughout the docs

## Best Next Red Tests In Domain Language

- "Azure /24 yields 251 usable addresses and starts at `.4`"
- "RFC6598 shared space is not RFC1918 private space"
- "IPv6 validation succeeds but IPv4 private-range classification rejects it"
- "A network lookup includes subnet facts, but a single-address lookup does not"
- "Cloudflare membership accepts both addresses and CIDR ranges"

## DDD Read

`subnetcalc` is the strongest current DDD candidate in the repo because it has:

- a real rule set
- clear input and output language
- multiple delivery shapes wrapped around the same core logic

That is a good place to push harder on a real domain model instead of letting
transport and hosting concerns dominate the language.
