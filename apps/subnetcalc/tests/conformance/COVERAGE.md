# Subnetcalc API Conformance Coverage

Specification source:

- `docs/ddd/contracts.md`
- `docs/ddd/ubiquitous-language.md`
- Current Go backend examples for provider ranges and network planning behavior

The harness is process-based HTTP contract testing. Run it against any backend
that exposes the subnetcalc API:

```bash
make -C apps/subnetcalc test-conformance SUBNETCALC_CONFORMANCE_BASE_URL=http://127.0.0.1:8090
```

## Coverage Matrix

| Contract Section | MUST Clauses | SHOULD Clauses | Tested | Passing | Divergent | Score |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| health | 1 | 0 | 1 | 1 | 0 | 100% |
| ipv4-subnet-info | 4 | 0 | 4 | 4 | 0 | 100% |
| ipv6-subnet-info | 1 | 0 | 1 | 1 | 0 | 100% |
| provider-ranges | 3 | 0 | 3 | 3 | 0 | 100% |
| network-plan | 1 | 0 | 1 | 1 | 0 | 100% |
| errors | 2 | 0 | 2 | 2 | 0 | 100% |

## Cases

| Case | Section | Level | Behavior |
| --- | --- | --- | --- |
| `SUBNETCALC-API-001` | health | MUST | Backend exposes healthy status. |
| `SUBNETCALC-API-010` | ipv4-subnet-info | MUST | Standard `/24` usable range and address count. |
| `SUBNETCALC-API-011` | ipv4-subnet-info | MUST | Azure reservations start usable range at `.4`. |
| `SUBNETCALC-API-012` | ipv4-subnet-info | MUST | AWS reservations match Azure reservation count. |
| `SUBNETCALC-API-013` | ipv4-subnet-info | MUST | OCI reservations start usable range at `.2`. |
| `SUBNETCALC-API-020` | ipv6-subnet-info | MUST | IPv6 total addresses use the submitted prefix. |
| `SUBNETCALC-API-030` | provider-ranges | MUST | AWS bundled provider range match. |
| `SUBNETCALC-API-031` | provider-ranges | MUST | OpenAI has no published bundled provider ranges. |
| `SUBNETCALC-API-032` | provider-ranges | MUST | Provider cache invalidation endpoint is present. |
| `SUBNETCALC-API-040` | network-plan | MUST | Network plan allocates sorted host requirements with cloud reservations. |
| `SUBNETCALC-API-050` | errors | MUST | Unsupported provider returns a client error. |
| `SUBNETCALC-API-051` | errors | MUST | Unsupported cloud mode returns a client error. |

## Known Gaps

- Provider cache refresh is covered in each backend's native tests with fake
  provider feed sources. The process harness only verifies the generic HTTP
  contract and invalidation endpoint, because refresh source injection differs
  by runtime and should not pull large live AWS/Azure feeds during default
  conformance runs.
- Authenticated modes are not part of this harness yet. Run the existing
  per-runtime auth tests for JWT, APIM, Easy Auth, and API key behavior.
