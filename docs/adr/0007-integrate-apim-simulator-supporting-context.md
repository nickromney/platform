# ADR 0007: Integrate APIM simulator as an in-repo supporting context

- Status: Accepted
- Recorded: 2026-05-08
- Supersedes: [ADR 0005](./0005-vendor-apim-simulator-runtime.md)

## Context

The platform repo no longer carries a narrow APIM simulator vendor subset under
`apps/subnetcalc/apim-simulator`. The live simulator source now sits at
`apps/apim-simulator`, with its own source, contracts, examples, tests,
documentation, Backstage catalog metadata, app-local compose workflows, and
release artifact tooling.

Subnetcalc still consumes APIM as an API mediation supporting context. The
breaking change is repository ownership and path shape, not a collapse of APIM
language into the subnet-calculation domain core.

## Decision

Treat `apps/apim-simulator` as the APIM simulator source for this repo.

The platform and Subnetcalc paths consume that integrated source directly:

- shared Docker Compose builds APIM from `apps/apim-simulator`
- Kubernetes image distribution builds the `subnetcalc-apim-simulator` image
  from the Image Catalog Module entry for `apps/apim-simulator`
- APIM behaviour contracts live in
  `apps/apim-simulator/contracts/contract_matrix.yml`
- Subnetcalc keeps APIM as a supporting context at the API mediation seam

Remove guidance that asks maintainers to edit an external simulator repo and
re-vendor a runtime subset into `apps/subnetcalc`.

## Consequences

- APIM simulator changes can land with the platform change that consumes them.
- Subnetcalc no longer owns an APIM vendored subtree; it only consumes APIM
  through mediation configuration and request paths.
- The old `apps/subnetcalc/apim-simulator` path and
  `apim-simulator.vendor.json` metadata are intentionally broken surfaces and
  should not be restored.
- Contract changes in APIM must update the simulator contract matrix and
  focused tests in the same branch.
- The APIM simulator remains a supporting context, not a Shared Kernel with
  Subnetcalc.

## Evidence

- [apps/apim-simulator](../../apps/apim-simulator)
- [apps/apim-simulator/contracts/contract_matrix.yml](../../apps/apim-simulator/contracts/contract_matrix.yml)
- [docker/compose/compose.yml](../../docker/compose/compose.yml)
- [kubernetes/workflow/image-catalog.json](../../kubernetes/workflow/image-catalog.json)
- [docs/ddd/contracts.md](../ddd/contracts.md)
