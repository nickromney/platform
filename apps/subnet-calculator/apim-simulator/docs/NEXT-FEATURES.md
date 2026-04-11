# Next Features

This file tracks open areas that would materially expand the simulator. It is not an acceptance log for work that has already shipped.

## Highest-Value Next Work

### Broader Sample Compatibility Coverage

Keep growing the curated APIM sample fixture set under [`tests/fixtures/apim_samples/`](../tests/fixtures/apim_samples/).

Good additions are:

- widely used policy patterns
- behaviours that are easy to verify locally
- cases where the simulator needs to clearly label support as `supported`, `adapted`, or `unsupported`

### Better Import Fidelity

Improve Terraform/OpenTofu and OpenAPI projection where it increases day-to-day usefulness:

- richer OpenAPI schema and request/response metadata projection
- clearer compatibility-report output for partially supported resources
- tighter mapping between imported metadata and the management API surface

### Broader Local Management Workflows

Expand low-risk local CRUD and operator-console workflows where they make the simulator easier to use:

- better editing flows for descriptive resources
- stronger persistence ergonomics for config-authored resources
- clearer management summaries for large imported configs

### More End-To-End Example Coverage

Prefer new examples that exercise shipped capabilities rather than speculative parity work:

- mixed auth flows
- richer mTLS examples
- policy-heavy examples that pair runtime behaviour with traces and OTEL

## Still Deferred

- External cache backends
- Full APIM expression-engine compatibility
- `quota-by-key` bandwidth enforcement
- Developer portal, CMS, email, and notification features
- Full ARM or SDK wire compatibility

## Bar For New Work

1. The feature must be testable locally.
2. The feature must improve learning, debugging, or iteration speed.
3. The feature must document any adapted behaviour instead of implying Azure parity.
