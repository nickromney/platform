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
6. When you change a documented contract, update
   [`contracts/contract_matrix.yml`](contracts/contract_matrix.yml) and mark the
   owning pytest case with `@pytest.mark.contract(...)` before you implement the
   code change.

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

## Downstream Vendoring

This repository is the authoritative source when another repo vendors
`apim-simulator`.

If you refresh a downstream mirror:

1. Vendor from a tag or a specific commit SHA.
2. Record the resolved commit in the downstream repo.
3. Do not hand-edit the vendored subtree and assume those edits will survive the
   next sync. Land source changes here first, then re-vendor.

For downstream builders that want a smaller context, use the runtime source
archive instead of the full repository:

```bash
make runtime-artifact
```

That writes `dist/apim-simulator-runtime-vX.Y.Z.zip` plus a `.sha256` file. The
archive contains only `.dockerignore`, `Dockerfile`, `LICENSE.md`, `app/`,
`contracts/`, `pyproject.toml`, and `uv.lock`, with the example-copying
Dockerfile line removed so platform Gitea can build it directly.

## Release Workflow

Use this when changes in `main` should become a published release and you want
the release commit and tag to stay immutable.

- `git checkout -b chore/release-X.Y.Z` - keep the bump reviewable before it lands.
- `make release VERSION=X.Y.Z` - synchronize the version markers and run the release gate.
- `git push -u origin chore/release-X.Y.Z` - open the release branch for review.
- `# merge the PR` - only tag the commit that actually landed on `main`.
- `git checkout main && git pull` - move to the merged release commit.
- `make release-tag VERSION=X.Y.Z` - create the immutable `vX.Y.Z` tag from `main`.
- `git push origin vX.Y.Z` - publish the tag so downstream mirrors can pin it
  and start the release workflow.

The release workflow verifies the tag matches `pyproject.toml`, publishes the
runtime source zip to the GitHub release, uploads the checksum, pushes
`ghcr.io/<owner>/apim-simulator`, and creates provenance attestations for both
the zip and image. Release image builds use the Dockerfile's Docker Hardened
Image defaults, so configure the `DHI_USERNAME` and `DHI_TOKEN` repository
secrets first. `DHI_PASSWORD` is accepted as a fallback secret name.

Manual `workflow_dispatch` runs can skip the image job, build an image without
pushing it, choose the `dhi` or `public` base-image profile, and optionally push
the manual image build to GHCR. Published tag releases ignore those manual
knobs: they always build from the Docker Hardened Image profile and push.

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
