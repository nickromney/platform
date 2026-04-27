# Local IDP Next Implementation Steps

## Summary

The repo now has a tested FastAPI IDP core, developer portal, SDK, MCP wrapper,
runtime adapter foundation, catalog entries, and HTTPS/FQDN Kubernetes manifests
for:

- `https://portal.127.0.0.1.sslip.io`
- `https://portal-api.127.0.0.1.sslip.io`

The next goal is to make those surfaces run end to end in the local kind stack,
then prove the same contract on Lima.

## Implementation Sequence

1. Build runnable platform images.
   - Add production Dockerfiles for `apps/idp-core` and `apps/idp-portal`.
   - Keep images small and non-root.
   - Serve the portal as static assets behind a minimal HTTP server.
   - Ensure the portal build uses `VITE_IDP_API_BASE_URL=https://portal-api.127.0.0.1.sslip.io`.
   - Wire both images into the existing local platform image build flow.
   - Expected image refs:
     - `localhost:30090/platform/idp-core:latest`
     - `localhost:30090/platform/idp-portal:latest`

2. Extend local image build tests.
   - Add red/green tests proving `build-local-platform-images` includes
     `idp-core` and `idp-portal`.
   - Keep dependency guardrails:
     - npm package versions exact
     - `.npmrc` uses `min-release-age=7`
     - uv projects use `exclude-newer = "7 days"`
   - Keep generated build outputs and `node_modules` out of git.

3. Run the kind stack to stage 900.
   - Use:
     ```bash
     make -C kubernetes/kind 900 apply AUTO_APPROVE=1
     ```
   - Do not interrupt long quiet stretches; use health/status probes from
     `skills/use-platform/SKILL.md` if needed.
   - Confirm these Argo CD apps exist and sync:
     - `idp`
     - `oauth2-proxy-idp-portal`
     - `oauth2-proxy-idp-core`

4. Verify HTTPS/FQDN behavior.
   - Check:
     ```bash
     curl -k https://portal-api.127.0.0.1.sslip.io/api/v1/runtime
     curl -k https://portal-api.127.0.0.1.sslip.io/api/v1/catalog/apps
     ```
   - Open:
     ```text
     https://portal.127.0.0.1.sslip.io
     ```
   - The developer portal must render the service catalog and call
     `portal-api`, not localhost.

5. Add browser E2E smoke.
   - Add Playwright coverage through HTTPS and SSO.
   - Test at minimum:
     - portal route loads after auth
     - runtime displays
     - catalog apps render
     - browser network calls target `portal-api.127.0.0.1.sslip.io`
   - Reuse the existing stage-900 SSO smoke harness patterns.

6. Replace placeholder API projections.
   - Replace `overall_state: unknown` with the existing `platform-status`
     projection.
   - Back `/api/v1/deployments`, `/api/v1/secrets`, and `/api/v1/scorecards`
     with catalog plus existing `idp-*` scripts.
   - Keep all mutation endpoints dry-run first.
   - Apply-mode mutations should remain `501` until request lifecycle,
     reconciliation, rollback, and audit semantics are specified.

7. Define and implement `idp-lite`.
   - Add a resource-conscious kind profile for <=16GB hosts.
   - Include:
     - kind
     - Gateway API/TLS
     - Gitea
     - Argo CD
     - SSO
     - developer portal
     - portal API
     - one sample app
     - minimal observability
   - Exclude or make optional:
     - heavy observability
     - extra sample apps
     - optional controllers not needed for the local IDP demo
   - Document expected resource use.

8. Prove Lima portability.
   - Run the same portal/API contract on `kubernetes/lima`.
   - Verify the same public FQDNs and API paths.
   - Any runtime-specific behavior must live behind the FastAPI runtime adapter,
     not in the portal UI, SDK, or MCP.

## Acceptance Criteria

- `portal` and `portal-api` are reachable through HTTPS on `*.127.0.0.1.sslip.io`.
- The developer portal renders catalog data through the portal API.
- The portal API is behind the same SSO/gateway pattern as the rest of the
  platform.
- Stage-900 kind apply passes health and SSO checks.
- Playwright covers the portal route through HTTPS and SSO.
- `make check-version` still passes dependency age gates and frontend budgets.
- `kubectl kustomize terraform/kubernetes/apps/idp` renders cleanly.
- `kubectl kustomize terraform/kubernetes/apps/platform-gateway-routes-sso`
  renders cleanly.
- No Terraform replacement logic is introduced.

## Verification Commands

```bash
bats tests/idp-core-components.bats tests/idp-portal-sdk-mcp.bats tests/local-idp-contracts.bats
cd apps/idp-core && UV_PROJECT_ENVIRONMENT=/tmp/platform-idp-core-venv uv run --extra dev pytest -q
cd apps/idp-mcp && uv run --with pytest pytest -q
cd apps/idp-portal && npm run build
kubectl kustomize terraform/kubernetes/apps/idp
kubectl kustomize terraform/kubernetes/apps/platform-gateway-routes-sso
cd terraform/kubernetes && tofu test -filter=tests/direct_workload_apps.tftest.hcl -filter=tests/gitops_features.tftest.hcl
make check-version
make -C kubernetes/kind 900 apply AUTO_APPROVE=1
make -C kubernetes/kind check-health
make -C kubernetes/kind check-sso-e2e
```

## Notes For The Next Agent

- Use red/green TDD for every new behavior.
- Update `docs/ddd/ubiquitous-language.md` whenever new domain terms or public
  surfaces are introduced.
- The repo/platform is the IDP. The developer portal is only one surface.
- Public short names are `portal` and `portal-api`; internal component names may
  remain `idp-core` and `idp-portal`.
- Do not run destructive reset/apply commands without understanding current
  local cluster state.
