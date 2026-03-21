# Platform SSO E2E (Playwright)

Browser tests that verify you can load each SSO-protected endpoint, complete the Dex local-login flow,
and exercise real post-login app behavior for the endpoints that support it.
They target the shared `*.127.0.0.1.sslip.io` endpoints, so they work against the Kind, Lima, or Slicer platform stacks.
The operator-facing HTTPS origin is `:443` on all three targets. Slicer still uses `:8443` for its raw local forwarder behind the Docker proxy, but the browser tests should hit the shared `https://*.127.0.0.1.sslip.io/` surface.
By default they now perform the deeper app actions. Set `SSO_E2E_VERIFY_APP_ACTIONS=0` only when you explicitly want login-only coverage.
When `enable_victoria_logs=true` in the active stage tfvars, the Grafana smoke path also verifies the `victorialogs` datasource/plugin and the `platform-logs` dashboard.
The target-specific `check-sso-e2e` wrappers no longer repair Slicer/Lima k3s apiserver OIDC settings before the browser run.
If you are testing an older Slicer or Lima cluster, rerun `900 apply` first or invoke that target's `configure-k3s-apiserver-oidc` command manually.
The repo uses project-local Playwright from `@playwright/test`; no global
`playwright` install is expected.

Full browser E2E is a host-oriented workflow. The devcontainer does not bake
Chromium runtime libraries anymore, so run `check-sso-e2e` from the host unless
you intentionally provision browser dependencies yourself.

## Setup

```bash
cd tests/kubernetes/sso
bun install
bun x playwright install chromium
```

Required local tooling:

- `bun`
- `node` (which provides `npm` and `npx`)

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

Defaults match the demo creds in the platform stack. Override with env vars if you changed them:

```bash
export DEX_DEV_LOGIN="demo@dev.test"
export DEX_DEV_PASSWORD="${PLATFORM_DEMO_PASSWORD}"

export DEX_UAT_LOGIN="demo@uat.test"
export DEX_UAT_PASSWORD="${PLATFORM_DEMO_PASSWORD}"

export DEX_ADMIN_LOGIN="demo@admin.test"
export DEX_ADMIN_PASSWORD="${PLATFORM_DEMO_PASSWORD}"
```
