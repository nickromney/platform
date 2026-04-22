# ADR 0002: Use cumulative stages and a reference variant

- Status: Accepted (retrospective)
- Recorded: 2026-04-21

## Context

The staged local-cluster model predates the recent DDD pass and became one of
the repo's most stable operator abstractions.

The local stack was first built around `subnetcalc` on the Docker-backed kind
path. Later variants came from concrete operator pressures rather than from a
desire to create separate domains:

- Lima became interesting because Docker Desktop licensing on commercial
  machines made a non-Docker-Desktop path worth proving
- Slicer followed once `slicer-mac` shipped with k3s, which made a local k3s
  variant an obvious route

The stage ladder remained durable even as the substrate changed.

Today:

- `kubernetes/kind` is the strongest full-confidence path
- `kubernetes/lima` and `kubernetes/slicer` converge on the same shared stack
  with different substrate mechanics
- the DDD comparison doc describes `kind` as the reference teaching variant and
  the others as adapter variants

## Decision

Keep the cumulative `100` through `900` stage model as the main operator
abstraction for the Kubernetes solution.

Treat:

- `kubernetes/kind` as the reference variant
- `kubernetes/lima` and `kubernetes/slicer` as variants that adapt the shared
  stack to other local runtimes

Use stable stage outcomes and product nouns where those are the real operator
language:

- `100` cluster available
- `200` Cilium
- `300` Hubble
- `400` Argo CD
- `500` Gitea
- `600` policies
- `700` app repos
- `800` observability
- `900` SSO

## Consequences

- Operators get one durable mental model across multiple variants.
- Variant-specific mechanics stay local to each subtree instead of redefining
  the shared stack language.
- `kind` naturally carries the strongest verification burden because it is the
  reference confidence path.
- Cross-variant work can compare operator outcomes first and substrate details
  second.

## Evidence

- [kubernetes/kind/README.md](../../kubernetes/kind/README.md)
- [docs/ddd/solution-variant-comparison.md](../ddd/solution-variant-comparison.md)
- [docs/ddd/ubiquitous-language.md](../ddd/ubiquitous-language.md)
- Current history: `platform` started with the staged kind path in place; later
  history added Lima and Slicer while preserving the staged operator model.
