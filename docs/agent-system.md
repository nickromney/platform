# platform: agent operating model

Adopted 6 October 2026 from local source and command inspection.
Local Kubernetes platform stack with shared workflows and multiple adapters.

## Read by intent

Start with the local agent guide and build manifest. For domain or behavior
changes, follow the owners below, then the relevant contract/test. These
documents retain product detail and historical evidence:

- [README.md](../README.md)
- [apps/README.md](../apps/README.md)
- [apps/platform-mcp/README.md](../apps/platform-mcp/README.md)
- [apps/apim-simulator/README.md](../apps/apim-simulator/README.md)
- [docs/reviews/README.md](reviews/README.md)

## System ownership

| Owner | Responsibility |
| --- | --- |
| [kubernetes/kind](../kubernetes/kind) | Stage-specific desired infrastructure and focused Make workflows. |
| [kubernetes/lima](../kubernetes/lima) | Stage-specific desired infrastructure and focused Make workflows. |
| [mk](../mk) | Stage-specific desired infrastructure and focused Make workflows. |
| [scripts/platform-workflow.sh](../scripts/platform-workflow.sh) | Shared workflow execution and human adapters. |
| [tools/platform-tui](../tools/platform-tui) | Shared workflow execution and human adapters. |
| [tools/platform-workflow-ui](../tools/platform-workflow-ui) | Shared workflow execution and human adapters. |
| [schemas/idp](../schemas/idp) | App/runtime contracts and domain cores. |
| [apps](../apps) | App/runtime contracts and domain cores. |
| [docs/ddd](../docs/ddd) | App/runtime contracts and domain cores. |
| [scripts/ci-receipt.sh](../scripts/ci-receipt.sh) | Exact-tree local CI evidence. |
| [docs/adr/0011-run-the-full-gate-locally-with-a-receipt.md](../docs/adr/0011-run-the-full-gate-locally-with-a-receipt.md) | Exact-tree local CI evidence. |

Intent selects the owning policy; that policy produces decisions or artifacts;
adapters perform effects; verification establishes the result. Change the
owner once and keep alternate surfaces on that same contract.

## Invariants

- Root make is informational; AUTO_APPROVE is supported, AUTO_APPLY is not.
- CI receipt matches exact tree including uncommitted/untracked nonignored files.
- Successful local tests do not prove stage deployment or kernel capability.

## Existing action interfaces

These are inspected command surfaces, not a report that they ran. Read current
help and recipes for arguments, dependencies and lifecycle hooks before use.
Examples containing placeholder paths or bracketed options are grammar.

| Command | Effects and evidence |
| --- | --- |
| `make` | Informational routing. |
| `make -C kubernetes/kind help` | Stage/actions discovery. |
| `make -C kubernetes/kind prereqs` | Runtime/platform prerequisites; not deployment acceptance. |
| `make lint && make test-ci` | Local gate and exact-tree receipt; expensive. |
| `make test-ci-linux` | Linux devcontainer gate; Docker/devcontainer prerequisites. |

## Observe, verify and retain

Establish source revision, dirty state and relevant input identity before
choosing an action. Keep intended settings, cached artifacts and observed
runtime state distinct. An existing artifact is not a freshness or readiness
claim. Use the smallest deterministic fixture at the changed seam first;
expand to process, browser, device or deployment checks only when that
claim needs them. Record unavailable evidence explicitly.

Retain the command/configuration, source and input identity, result, limitation
and next discriminating check. Reuse evidence only while its relevant inputs
remain applicable. Promote a reproducible failure to a regression fixture,
a design decision to its owning document, and a repeated operator correction
to one concise guide rule. Keep private observations in private artifacts.

## Implemented plan for this pass

- [x] Map current source ownership and existing interfaces.
- [x] Make command effects and evidence limits discoverable.
- [x] Route agent work here and retain detailed product plans at their owners.

Acceptance: owner paths and document links resolve; current instructions
match inspected source; catalog hashes bind this context to the reviewed
bytes. This is documentation/control navigation acceptance. Product runtime
checks retain their own scope and are not certified by this pass.

## Project decisions

Use the repo-local use-platform skill and focused Makefile as the entrypoint. Desired stage configuration, observed runtime status and local CI receipts are separate evidence. Traverse stage/app intent to shared workflow to concrete command to runtime verifier. Attach platform target, env-file identity, selected stages/apps, source revision and dated acceptance result to a runtime claim; never infer full-stack readiness from prerequisites or a Go test pass. Keep adapters delegated to scripts/platform-workflow.sh and avoid another plan engine. Reuse exact-tree CI receipts while the tree matches, run focused tests during iteration and run the documented host/Linux gates once the change is ready. Add confirmed cross-platform failures to the owning regression suite and link them from current STATUS, leaving historical handoffs archived.
