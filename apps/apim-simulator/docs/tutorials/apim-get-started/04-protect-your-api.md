# 4 - Protect Your API

Source: [Tutorial: Transform and protect your API](https://learn.microsoft.com/en-us/azure/api-management/transform-api)

Simulator status: Supported

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These commands assume `tutorial-api` and `tutorial-key` already exist. If not,
run steps 1 and 2 first or use `./docs/tutorials/apim-get-started/tutorial02.sh --setup`.

Apply an API policy that adds a custom header and rate-limits by subscription:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/policies/api/tutorial-api" \
  --data '{"xml":"<policies><inbound><rate-limit-by-key calls=\"3\" renewal-period=\"15\" counter-key=\"@(context.Subscription.Id)\" /><base /></inbound><backend><base /></backend><outbound><set-header name=\"Custom\" exists-action=\"override\"><value>My custom value</value></set-header><base /></outbound><on-error><base /></on-error></policies>"}'
```

Verify the transform and throttling:

```bash
curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "$APIM_BASE/tutorial-api/health"
curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "$APIM_BASE/tutorial-api/health"
curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "$APIM_BASE/tutorial-api/health"
curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "$APIM_BASE/tutorial-api/health"
```

## What Mapped Cleanly

- API-level policies
- outbound header transforms
- request throttling with `rate-limit-by-key`

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial04.sh --setup
./docs/tutorials/apim-get-started/tutorial04.sh --verify
```

Use `--setup` to have [`tutorial04.sh`](tutorial04.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial04.sh --verify` output:

```text
Applying transform and rate-limit policy to 'tutorial-api'
{
  "contains_custom_header": true,
  "contains_rate_limit": true,
  "scope_name": "tutorial-api",
  "scope_type": "api"
}

Verifying transform and throttling
$ curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "http://localhost:8000/tutorial-api/health"
{
  "custom_header": "My custom value",
  "path": "/api/health",
  "status": "ok",
  "status_code": 200
}

$ curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "http://localhost:8000/tutorial-api/health"
{
  "body_text": "Rate limit exceeded",
  "retry_after_present": true,
  "status_code": 429
}
```

## Differences From Azure APIM

- The simulator uses the XML policy editor directly rather than the Azure portal gallery UI.
