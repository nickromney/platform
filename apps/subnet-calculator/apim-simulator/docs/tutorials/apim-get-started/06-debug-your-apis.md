# 6 - Debug Your APIs

Source: [Tutorial: Debug your APIs](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-api-inspector)

Simulator status: Adapted

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These commands assume `tutorial-api` and `tutorial-key` already exist. If not,
run steps 1 and 2 first or use `./docs/tutorials/apim-get-started/tutorial02.sh --setup`.

Request a trace:

```bash
curl -i \
  -H "Ocp-Apim-Subscription-Key: tutorial-key" \
  -H "x-apim-trace: true" \
  "$APIM_BASE/tutorial-api/health"
```

Copy the `x-apim-trace-id` response header, then inspect the trace:

```bash
curl -sS "$APIM_BASE/apim/trace/<trace-id>"
```

You can also browse recent traces:

```bash
curl -sS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  "$APIM_BASE/apim/management/traces"
```

## What Mapped Cleanly

- Per-request policy execution detail
- Backend selection and upstream URL inspection
- Trace-first debugging workflow

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial06.sh --setup
./docs/tutorials/apim-get-started/tutorial06.sh --verify
```

Use `--setup` to have [`tutorial06.sh`](tutorial06.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial06.sh --verify` output:

```text
Verifying stored trace details
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/traces"
{
  "matching_traces": 1
}

$ curl -sS "http://localhost:8000/apim/trace/<trace-id>"
{
  "correlation_id": "tutorial06-health",
  "status": 200,
  "upstream_url": "http://mock-backend:8080/api/health"
}
```

## Differences From Azure APIM

- The simulator uses `x-apim-trace: true` directly.
- It does not implement Azure's time-limited debug-token flow for trace authorization.
