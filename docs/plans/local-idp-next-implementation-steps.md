# Local IDP Next Implementation Steps

## Review Baseline

This plan was reviewed against the current platform repo and the cloned
`~/Developer/personal/public-site` source for internaldeveloperplatform.org.

The repo already has:

- FastAPI IDP core, Backstage developer portal, SDK, and MCP client code.
- Runtime adapters for `kind`, `lima`, and `generic_kubernetes`.
- Catalog, deployment, secret, scorecard, runtime, action, and audit schemas.
- Kubernetes manifests for `idp-core` and `backstage`.
- SSO HTTPRoutes for:
  - `https://portal.127.0.0.1.sslip.io`
  - `https://portal-api.127.0.0.1.sslip.io`
- Argo CD Applications for:
  - `idp`
  - `oauth2-proxy-backstage`
  - `oauth2-proxy-idp-core`

At review start, the repo did not have runnable IDP container images. The
current implementation adds those images, host-local-cache wiring, SSO browser
coverage, API projection tests, and an `950-local-idp` kind profile. The remaining
blocking gap is live stack proof: rebuild/apply kind stage 900, then run the
health and browser SSO checks against that freshly applied stack.

The public-site definition is important: the repo/platform is the Internal
Developer Platform. The developer portal is one interface over the platform,
alongside API, SDK, MCP, CLI, and TUI surfaces. Keep new work aligned with the
IDP capabilities described there: golden paths, self-service, service catalog,
environment management, deployment management, application configuration,
infrastructure orchestration, and RBAC.

## Implementation Status

- Complete in the current worktree: chunks 1, 2, 4, 5, 6, and 8.
- Static/render proof complete for chunk 3: IDP and SSO gateway kustomizations
  render, and direct workload/validation OpenTofu tests pass.
- Remaining live proof for chunk 3: run `make -C kubernetes/kind 900 apply
  AUTO_APPROVE=1`, then `check-health`, `check-gateway-urls`, `check-sso`, and
  `check-sso-e2e`.
- Remaining chunk 7: Lima live apply and SSO proof after kind is green.

## TDD Rules

Every implementation chunk below must use red/green TDD:

1. Add or update the smallest relevant test first.
2. Run only that focused test and capture the failing result.
3. Implement the minimum production change.
4. Re-run the same focused test until it passes.
5. Run the listed broader verification for that chunk.

Do not mix chunks unless a test proves the dependency is required. Less powerful
handoff agents should be assigned one chunk at a time.

## Non-Negotiables

- Do not make the portal the IDP. It is only one product surface.
- Runtime-specific behavior belongs behind the FastAPI runtime adapter.
- The portal, SDK, MCP, and future TUI must call the HTTP API, not shell out to
  `make`, `kubectl`, Terraform, or repo scripts.
- Mutating API endpoints stay dry-run first.
- Apply-mode mutations stay `501` until request lifecycle, reconciliation,
  rollback, audit, and authorization semantics are specified.
- The public `portal-api` route is SSO-protected. Plain `curl -k
  https://portal-api.../api/v1/runtime` should prove auth protection or redirect,
  not unauthenticated JSON access.
- No Terraform replacement logic should be introduced.

## Handoff Chunks

### 1. Container Image Contracts

Ownership:

- `apps/idp-core/`
- `apps/backstage/`
- New focused tests under `tests/`

Red tests:

- Add container contract coverage, for example
  `tests/local-idp-container-images.bats`.
- Prove both Dockerfiles are missing before implementation.
- Add an `idp-core` pytest for configurable catalog path, because the current
  app reads `catalog/platform-apps.json` from the repo checkout. A container
  must either preserve that path or use an explicit `IDP_CATALOG_PATH`.
- Add a Backstage build/config test proving the portal is configured for
  `https://portal.127.0.0.1.sslip.io`, uses the local platform catalog, and
  includes software templates for self-service workflows.

Green implementation:

- Add `apps/idp-core/Dockerfile`.
  - Use the existing Python/uv style from nearby app Dockerfiles.
  - Run on port `8080`.
  - Run as non-root.
  - Keep `HOME=/tmp`.
  - Copy or configure the catalog so `/api/v1/catalog/apps` works in the image.
  - Prefer `IDP_CATALOG_PATH` so tests can inject a fixture.
- Add `apps/backstage/Dockerfile`.
  - Build and run inside a Node 22 container so host `nvm` state is irrelevant.
  - Use Backstage's pinned Yarn release and lockfile.
  - Use SQLite for the local Backstage database; do not share Keycloak's
    Postgres.
  - Serve the Backstage backend/app on port `7007`.
  - Run as non-root and keep write state under `/tmp`.
- Add `.dockerignore` files where needed so `node_modules`, build output, test
  artifacts, and local run state cannot enter image contexts.

Focused verification:

```bash
bats tests/local-idp-container-images.bats
cd apps/idp-core && UV_PROJECT_ENVIRONMENT=/tmp/platform-idp-core-venv uv run --extra dev pytest -q
cd apps/backstage && docker build -t platform/backstage:test -f Dockerfile .
```

### 2. Local Platform Image Build Flow

Ownership:

- `kubernetes/kind/scripts/build-local-platform-images.sh`
- `terraform/kubernetes/variables.tf`
- `terraform/kubernetes/locals.tf`
- `terraform/kubernetes/scripts/sync-gitea.sh`
- `terraform/kubernetes/scripts/sync-gitea-policies.sh`
- `kubernetes/kind/targets/kind.tfvars`
- `kubernetes/lima/targets/lima.tfvars`
- `kubernetes/slicer/targets/slicer.tfvars`
- Focused Bats/OpenTofu tests

Accuracy note:

- Source manifests currently use `localhost:30090/platform/idp-*.latest`.
  That is the Gitea registry shape, but it is not a safe first-boot source for
  host-built IDP images.
- The stage-900 Make flow already builds platform shortcut images into the
  host local cache when `prefer_external_platform_images=true`.
- Therefore the green path should build `idp-core` and `backstage` into the
  host cache and render runtime-specific pull refs into the policies repo.

Expected pushed refs:

- Host push target: `127.0.0.1:5002/platform/idp-core:latest`
- Host push target: `127.0.0.1:5002/platform/backstage:latest`

Expected rendered pull refs:

- kind: `host.docker.internal:5002/platform/idp-core:latest`
- kind: `host.docker.internal:5002/platform/backstage:latest`
- Lima: `host.lima.internal:5002/platform/idp-core:latest`
- Lima: `host.lima.internal:5002/platform/backstage:latest`
- Slicer: `192.168.64.1:5002/platform/idp-core:latest`
- Slicer: `192.168.64.1:5002/platform/backstage:latest`

Red tests:

- Extend existing build-flow tests or add focused tests proving
  `build-local-platform-images` includes `idp-core` and `backstage`.
- Add Terraform tests proving `external_platform_image_refs` accepts the new
  `idp-core` and `backstage` keys.
- Add a render test proving the policies repo render rewrites IDP image refs
  when `prefer_external_platform_images=true`.

Green implementation:

- Extend `build-local-platform-images.sh` to build and push:
  - `platform/idp-core:latest`
  - `platform/backstage:latest`
- Add `idp-core` and `backstage` to the supported
  `external_platform_image_refs` keys.
- Add target-specific external platform image refs to kind, Lima, and Slicer.
- Export those refs through `sync-gitea.sh`.
- Rewrite `terraform/kubernetes/apps/idp/all.yaml` during
  `sync-gitea-policies.sh` when external platform images are preferred.
- Include the new refs in `policies_repo_render_hash` so changes force a
  policies repo sync.

Focused verification:

```bash
bats tests/validate-docker-optimization-contracts.bats
cd terraform/kubernetes && tofu test -filter=tests/validations.tftest.hcl -filter=tests/direct_workload_apps.tftest.hcl
make -C kubernetes/kind build-local-platform-images DRY_RUN=1
```

### 3. Kustomize, Argo CD, And Gateway Readiness

Ownership:

- `terraform/kubernetes/apps/idp/`
- `terraform/kubernetes/apps/platform-gateway-routes-sso/`
- `terraform/kubernetes/tests/`
- Existing health/check scripts only if tests prove a gap

Red tests:

- Add or extend tests proving the IDP manifests render cleanly.
- Add or extend tests proving the IDP Argo CD Application is created only when
  SSO is enabled.
- Add tests proving the two oauth2-proxy IDP Applications are generated with
  the expected upstreams and callback URLs.

Green implementation:

- Keep `idp-core` and `backstage` in the `idp` namespace.
- Keep public short names as `portal` and `portal-api`.
- Keep internal component names as `idp-core` and `backstage`.
- Do not add image pull secrets if the rendered refs use the unauthenticated
  host local cache.
- Preserve the existing SSO/gateway pattern.

Focused verification:

```bash
kubectl kustomize terraform/kubernetes/apps/idp
kubectl kustomize terraform/kubernetes/apps/platform-gateway-routes-sso
cd terraform/kubernetes && tofu test -filter=tests/direct_workload_apps.tftest.hcl -filter=tests/gitops_features.tftest.hcl
```

### 4. HTTPS And SSO Browser Smoke

Ownership:

- `tests/kubernetes/sso/tests/sso-smoke.spec.ts`
- `tests/kubernetes/sso/README.md`
- Target Makefile checks only if the wrapper needs new environment flags

Red tests:

- Add Playwright coverage for the developer portal route before the portal is
  expected to pass.
- Add coverage that browser network calls target
  `portal-api.127.0.0.1.sslip.io`.
- Add coverage for the Portal API through SSO after browser login.

Green implementation:

- Add a `developer-portal` target using the same oauth2-proxy login helper.
- After login, assert:
  - the portal route loads
  - runtime is displayed
  - service catalog entries render
  - no API calls target `localhost`
  - at least one response URL uses `portal-api.127.0.0.1.sslip.io`
- Add a Portal API target or post-login check that verifies
  `/api/v1/runtime` and `/api/v1/catalog/apps` return JSON after auth.
- Keep unauthenticated curl checks limited to proving SSO protection, for
  example redirect/401/403 behavior.

Focused verification:

```bash
make -C kubernetes/kind check-sso-e2e
```

### 5. API Projection Quality

Ownership:

- `apps/idp-core/app/`
- `apps/idp-core/tests/`
- `terraform/kubernetes/scripts/idp-*.sh` only when needed
- `scripts/platform-status.sh` integration only through an adapter boundary

Current state:

- `/api/v1/status` returns `overall_state: unknown`.
- `/api/v1/deployments`, `/api/v1/secrets`, and `/api/v1/scorecards` are
  catalog-derived first-pass read models.

Red tests:

- Add pytest coverage for a status projection that does not return
  `overall_state: unknown` when a status provider fixture is available.
- Add tests for catalog-derived deployments, secrets, and scorecards that match
  the JSON schemas.
- Add tests proving apply-mode mutations still return `501`.

Green implementation:

- Put status/read-model integration behind the runtime adapter.
- Host-side development may call `scripts/platform-status.sh --output json`
  through an injectable provider.
- In-cluster `idp-core` must not assume host Docker, host kubeconfigs, or repo
  scripts are available. If a projection cannot be safely collected in-cluster,
  return an explicit source/status field rather than pretending to have host
  state.
- Keep portal, SDK, and MCP clients unchanged except for consuming richer API
  fields.

Focused verification:

```bash
cd apps/idp-core && UV_PROJECT_ENVIRONMENT=/tmp/platform-idp-core-venv uv run --extra dev pytest -q
python3 scripts/validate-json-schema.py schemas/idp/status.schema.json <sample-status-json>
```

### 6. `950-local-idp` Profile

Ownership:

- `kubernetes/kind/`
- `terraform/kubernetes/`
- `docs/`
- Focused Makefile and OpenTofu tests

Red tests:

- Add a test for the chosen public entrypoint, for example a new
  `make -C kubernetes/kind 950-local-idp plan`.
- Add tests proving the lite profile includes:
  - kind
  - Gateway API/TLS
  - Gitea
  - Argo CD
  - SSO
  - developer portal
  - portal API
  - one sample app
- Add tests proving heavy optional components are disabled or opt-in.

Green implementation:

- Keep the stage model cumulative.
- Prefer a target/profile override file over a parallel stack.
- Use external workload/platform images to avoid requiring the in-cluster
  Actions runner on <=16GB hosts.
- Document expected CPU, memory, disk, and startup tradeoffs.
- Exclude or make optional:
  - Loki
  - Tempo
  - SigNoz
  - VictoriaLogs
  - extra sample apps
  - optional controllers not needed for the local IDP demo

Focused verification:

```bash
make -C kubernetes/kind 950-local-idp plan
make -C kubernetes/kind check-stage-monotonicity
```

### 7. Lima Portability

Ownership:

- `kubernetes/lima/`
- `terraform/kubernetes/`
- `apps/idp-core/app/adapters.py`
- SSO E2E tests if runtime-specific assumptions appear

Prerequisite:

- Do not start this chunk until kind stage-900 portal/API passes through SSO.

Red tests:

- Add Lima-specific tests proving the rendered IDP image refs use
  `host.lima.internal:5002`.
- Add adapter tests proving runtime-specific behavior stays behind the FastAPI
  adapter and not in the portal UI, SDK, or MCP.

Green implementation:

- Reuse the same Dockerfiles and build script.
- Reuse the same public FQDNs and API paths.
- Keep Lima host gateway proxy requirements in the Makefile wrapper, not in
  portal code.

Focused verification:

```bash
make -C kubernetes/lima 900 apply AUTO_APPROVE=1
make -C kubernetes/lima check-health
make -C kubernetes/lima check-sso-e2e
```

### 8. Documentation And Language

Ownership:

- `docs/ddd/ubiquitous-language.md`
- `docs/ddd/contracts.md`
- IDP plan docs under `docs/plans/`

Red tests:

- Extend existing Bats coverage when adding public domain terms or surfaces.

Green implementation:

- Keep language aligned with internaldeveloperplatform.org:
  - IDP means the whole internal developer platform.
  - Developer portal means one UI over IDP capabilities.
  - Service catalog, golden paths, self-service actions, environment
    management, deployment management, application configuration,
    infrastructure orchestration, and RBAC should remain explicit concepts.

Focused verification:

```bash
bats tests/local-idp-contracts.bats
```

## End-To-End Acceptance Criteria

- `idp-core` and `backstage` images build reproducibly and run as non-root.
- Stage-900 kind apply builds/pushes IDP images before the IDP manifests need
  them.
- Rendered kind manifests pull IDP images from the host local cache, not a
  first-boot Gitea registry dependency.
- `portal` and `portal-api` are reachable through HTTPS on
  `*.127.0.0.1.sslip.io`.
- Public `portal-api` is SSO-protected.
- Browser E2E proves authenticated JSON access to Portal API.
- The developer portal is Backstage and renders the platform catalog plus at
  least one software-template self-service workflow.
- Browser network calls do not target localhost or raw loopback.
- Stage-900 kind apply passes health, gateway URL, and SSO E2E checks.
- Lima proves the same portal/API contract without portal, SDK, or MCP rewrites.
- `make check-version` still passes dependency age gates and frontend budgets.
- Kustomize and OpenTofu tests pass for IDP, gateway routes, direct apps, and
  GitOps features.
- Apply-mode mutating API calls still return `501`.
- No Terraform replacement logic is introduced.

## Verification Command Set

Use focused tests during each red/green loop. Before handing off the full
implementation, run:

```bash
bats tests/idp-core-components.bats tests/idp-backstage-sdk-mcp.bats tests/local-idp-contracts.bats
bats tests/local-idp-container-images.bats
bats kubernetes/kind/tests/makefile.bats
cd apps/idp-core && UV_PROJECT_ENVIRONMENT=/tmp/platform-idp-core-venv uv run --extra dev pytest -q
cd apps/idp-mcp && uv run --with pytest pytest -q
cd apps/backstage && docker build -t platform/backstage:test -f Dockerfile .
kubectl kustomize terraform/kubernetes/apps/idp
kubectl kustomize terraform/kubernetes/apps/platform-gateway-routes-sso
cd terraform/kubernetes && tofu test -filter=tests/direct_workload_apps.tftest.hcl -filter=tests/gitops_features.tftest.hcl -filter=tests/validations.tftest.hcl
make -n -C kubernetes/kind 950-local-idp plan
make -C kubernetes/kind build-local-platform-images DRY_RUN=1
cd tests/kubernetes/sso && PLATFORM_DEMO_PASSWORD=dummy bun x playwright test --list
make check-version
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
make -C kubernetes/kind check-sso-e2e
```

Only run Lima after kind passes:

```bash
make -C kubernetes/lima 900 apply AUTO_APPROVE=1
make -C kubernetes/lima check-health
make -C kubernetes/lima check-sso-e2e
```

## Notes For The Next Agent

- Start with the smallest failing test for your assigned chunk.
- Record the exact red command and green command in your handoff notes.
- Do not run destructive reset commands unless the current local cluster state
  has been inspected and the operator intent is clear.
- Do not treat a quiet stage apply as failure. Use `check-health`,
  `check-gateway-urls`, `check-sso`, and `status` probes from the
  `use-platform` skill while the apply keeps running.
