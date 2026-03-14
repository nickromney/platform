# Platform SSO E2E (Playwright)

Browser tests that verify you can load each SSO-protected endpoint, complete the Dex local-login flow,
and exercise real post-login app behavior for the endpoints that support it.
They target the shared `*.127.0.0.1.sslip.io` endpoints, so they work against the Kind, Lima, or Slicer platform stacks.
The runner derives the HTTPS host port from the active stage tfvars, so Kind/Lima stay on `443` while Slicer uses `:8443`.
By default they now perform the deeper app actions. Set `SSO_E2E_VERIFY_APP_ACTIONS=0` only when you explicitly want login-only coverage.

## Setup

```bash
cd tests/kubernetes/sso
npm install
npx playwright install chromium
```

## Run

```bash
npm test
```

Headed mode:

```bash
npm run test:headed
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
export DEX_DEV_PASSWORD="password123"

export DEX_UAT_LOGIN="demo@uat.test"
export DEX_UAT_PASSWORD="password123"

export DEX_ADMIN_LOGIN="demo@admin.test"
export DEX_ADMIN_PASSWORD="password123"
```
