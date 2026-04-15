# Contributing to platform

This repository is a mix of platform engineering labs, reproducible examples,
and working infrastructure experiments. Contributions are welcome, but the bar
is intentionally high because the code is meant to stay runnable and useful.

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
3. If a change affects cloud resources, cluster behaviour, networking, auth, or
   bootstrap flows, assume review will look for operational detail, not just
   code style.

## What Good Pull Requests Look Like

1. One concern per pull request. Keep the scope narrow.
2. Explain the problem being solved and the tradeoffs you chose.
3. Include the exact validation you ran. If you did not run tests, say so.
4. Update the relevant README or docs when commands, prerequisites, topology,
   ports, or expected behaviour change.
5. Call out breaking changes, secrets handling, cloud cost implications, and
   rollback considerations when they apply.
6. Keep generated churn out of the diff unless it is required for the change.

## Commit Messages and Releases

This repository is set up for explicit release-prep commits plus `v`-prefixed
git tags.

Use conventional commit messages where practical so release previews and
release notes stay useful.

Useful entrypoints:

1. `make check-version` to verify the root workflow pins, vendored
   `apim-simulator` metadata, and repo-local dependency age gates before a
   release.
2. `make release-dry-run VERSION=X.Y.Z` to preview the release-prep commit.
3. `make release VERSION=X.Y.Z` on a clean release branch to update `VERSION`,
   run the release gate, and create the release-prep commit.
4. Merge the release branch.
5. `make release-tag VERSION=X.Y.Z` from updated `main` to create the
   annotated `vX.Y.Z` tag.

`make release` and `make release-tag` are idempotent for already-prepared or
already-tagged releases.

## Repository Shape

Use the repository structure as a guide when deciding where work belongs:

- `apps/` contains application and reference implementation work.
- `kubernetes/` contains local cluster setup and operational helpers.
- `terraform/` contains infrastructure definitions and supporting docs.
- `sd-wan/` contains network lab work and validation flows.
- `tests/` contains smoke, integration, and end-to-end coverage.

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
