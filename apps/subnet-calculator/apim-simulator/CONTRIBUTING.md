# Contributing to apim-simulator

This repository is a mix of APIM simulation work, reproducible examples, and
practical local testing flows. Contributions are welcome, but the bar is
intentionally high because the code is meant to stay runnable and useful.

## The Critical Rule

You must understand your change.

If you used AI, read [AI_POLICY.md](AI_POLICY.md). If you cannot explain what
your change does, how to validate it, and what it might break, do not submit
it.

## Before You Start

1. For anything non-trivial, open an issue first or comment on an existing one
   so the direction is clear before you spend time building it.
2. Small documentation fixes, typo fixes, and tightly scoped bug fixes can go
   straight to a pull request.
3. If a change affects gateway behaviour, auth flows, Docker or Compose
   topology, observability, management APIs, or compatibility tooling, assume
   review will look for operational detail, not just code style.

## What Good Pull Requests Look Like

1. One concern per pull request. Keep the scope narrow.
2. Explain the problem being solved and the tradeoffs you chose.
3. Include the exact validation you ran. If you did not run tests, say so.
4. Update the relevant README or docs when commands, prerequisites, ports, API
   behaviour, or expected runtime flows change.
5. Call out breaking changes, secrets handling, and rollout or rollback
   considerations when they apply.
6. Keep generated churn out of the diff unless it is required for the change.

## Validation

Use the smallest relevant validation surface for your change:

1. `make lint-check` for Python formatting and lint checks without rewriting
   files.
2. `make test` for the Python and shell test suites.
3. `make frontend-check` for the UI and demo frontend checks.
4. `make compat` and `make compat-report` for APIM compatibility work.
5. The relevant `make up-*`, `make smoke-*`, or `make verify-*` flow when your
   change affects a running stack.

## Repository Shape

Use the repository structure as a guide when deciding where work belongs:

- [`app/`](app/) contains the simulator implementation.
- [`config/`](config/) contains local simulator configuration.
- [`docs/`](docs/) contains operator and tutorial documentation.
- [`examples/`](examples/) contains demo applications and teaching flows.
- [`observability/`](observability/) contains OTEL and local monitoring assets.
- [`scripts/`](scripts/) contains local automation and helper tooling.
- [`tests/`](tests/) contains Python and shell coverage.
- [`ui/`](ui/) contains the operator console.

If your change introduces a new workflow, document it close to the code it
affects and link it from the nearest existing README.

## AI Usage

AI-assisted contributions are allowed, but disclosure and human understanding
are mandatory. Read [AI_POLICY.md](AI_POLICY.md) before submitting anything
AI-assisted.

## Licensing

By submitting a contribution to this repository, you agree that your
contribution is provided under the same licence as the repository:
[LICENSE.md](LICENSE.md).

That means contributions are accepted under FSL-1.1-MIT now, with the same MIT
future-license conversion schedule that applies to the rest of the repository.

## Review Expectations

Please be concise, factual, and specific. Low-context feature dumps, speculative
pull requests, and generic AI slop are unlikely to be reviewed favorably.
