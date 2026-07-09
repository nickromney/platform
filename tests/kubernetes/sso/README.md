# Platform SSO E2E (Playwright)

Browser tests that verify you can load each SSO-protected endpoint, complete the
configured OIDC provider login flow, and exercise real post-login app behavior
for the endpoints that support it.
They target the shared `*.127.0.0.1.sslip.io` endpoints, so they work against the Kind or Lima platform stacks.
The operator-facing HTTPS origin is `:443` on all three targets. Lima still uses `:8443` for its raw local forwarder behind the Docker proxy, but the browser tests should hit the shared `https://*.127.0.0.1.sslip.io/` surface.
By default they now perform the deeper app actions. Set `SSO_E2E_VERIFY_APP_ACTIONS=0` only when you explicitly want login-only coverage.
When `enable_victoria_logs=true` in the active stage tfvars, the Grafana smoke path also verifies the `victorialogs` datasource/plugin and the `platform-logs` dashboard.
The developer portal smoke path signs in through oauth2-proxy, verifies Backstage renders the software catalog without the Guest sign-in flow, and checks browser API traffic does not target localhost.
The Portal API smoke path is also browser-authenticated through SSO and verifies `/api/v1/runtime` and `/api/v1/catalog/apps` return JSON after login.
Do not add unauthenticated curl expectations for those JSON endpoints here; the public `portal-api` route is intentionally SSO-protected.
The target-specific `check-sso-e2e` wrappers no longer repair Lima/Lima k3s apiserver OIDC settings before the browser run.
If you are testing an older Lima or Lima cluster, rerun `900 apply` first or invoke that target's `configure-k3s-apiserver-oidc` command manually.
The repo uses project-local Playwright from `@playwright/test`; no global
`playwright` install is expected.

Full browser E2E now works in the devcontainer too. By default,
`tests/kubernetes/sso/run.sh` runs the suite in the matching
`mcr.microsoft.com/playwright:v<playwright-core>-noble` image, which is listed
in the local-cluster preload cache and digest lock. That keeps reset runs from
depending on host Playwright browser caches removed by `clean-local-state`.

Set `PLATFORM_PLAYWRIGHT_MODE=native` when you explicitly want host-native
Playwright. Native mode verifies the pinned Playwright browser cache before
tests start, probes the Playwright CDN before installing, and then runs without
mid-test browser downloads. Set `PLAYWRIGHT_SKIP_CDN_PREFLIGHT=1` only when that
preflight is known to be a false negative. `PLATFORM_PLAYWRIGHT_CHANNEL=chrome`
is a native-mode fallback that uses system Chrome with the usual
browser-version drift tradeoff.

## Setup

```bash
cd tests/kubernetes/sso
bun install
../../../kubernetes/scripts/ensure-playwright-browsers.sh --execute
```

Required local tooling:

- `bun`
- `node`
- `docker` for the default Docker-backed browser mode

## Run

```bash
bun run test
```

Headed mode:

```bash
bun run test:headed
```

From the repo root with kind:

```bash
cd kubernetes/kind
HEADED=1 make check-sso-e2e
```

Native host-browser mode:

```bash
PLATFORM_PLAYWRIGHT_MODE=native make check-sso-e2e
```

Run only the authenticated MCP Inspector and D2 render/export flow:

```bash
cd kubernetes/kind
SSO_E2E_TEST_GREP="mcp-console: load and login" make check-sso-e2e
```

Slow it down to watch interactions:

```bash
PW_SLOWMO=250 HEADED=1 make check-sso-e2e
```

Capture screenshots on success (after login, and for sentiment dev/uat after clicking Analyze):

```bash
SSO_E2E_CAPTURE=1 HEADED=1 make check-sso-e2e
```

If Sentiment’s `/api/v1/comments` intermittently returns 5xx during warmup, the test retries a few times.
You can disable deeper app actions or increase retries explicitly:

```bash
SSO_E2E_VERIFY_APP_ACTIONS=0 make check-sso-e2e
SSO_E2E_SENTIMENT_ANALYZE_RETRIES=5 make check-sso-e2e
```

## Credentials

Defaults match the demo creds in the platform stack. Override with provider-neutral
env vars if you changed them:

```bash
export OIDC_DEV_LOGIN="demo@dev.test"
export OIDC_DEV_PASSWORD="${PLATFORM_DEMO_PASSWORD}"

export OIDC_UAT_LOGIN="demo@uat.test"
export OIDC_UAT_PASSWORD="${PLATFORM_DEMO_PASSWORD}"

export OIDC_ADMIN_LOGIN="demo@admin.test"
export OIDC_ADMIN_PASSWORD="${PLATFORM_DEMO_PASSWORD}"
```

The older `DEX_*` variables remain accepted for Compose and compatibility
checks, and `KEYCLOAK_*` variables are accepted when you want the provider name
to be explicit.
