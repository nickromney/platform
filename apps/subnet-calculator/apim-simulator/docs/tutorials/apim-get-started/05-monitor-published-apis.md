# 5 - Monitor Published APIs

Source: [Tutorial: Monitor published APIs](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-use-azure-monitor)

Simulator status: Adapted

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These commands assume `tutorial-api` and `tutorial-key` already exist. If not,
run steps 1 and 2 first or use `./docs/tutorials/apim-get-started/tutorial02.sh --setup`.

Restart on the OTEL stack so you have logs, traces, and metrics:

```bash
make down
make up-otel
```

Send a few requests:

```bash
curl -sS -H "Ocp-Apim-Subscription-Key: tutorial-key" \
  -H "x-apim-trace: true" \
  -H "x-correlation-id: tutorial05-health" \
  "$APIM_BASE/tutorial-api/health"

curl -sS -H "Ocp-Apim-Subscription-Key: tutorial-key" \
  -H "x-apim-trace: true" \
  -H "x-correlation-id: tutorial05-echo" \
  "$APIM_BASE/tutorial-api/echo"
```

Then inspect:

- Grafana dashboards: `http://localhost:3001`
- recent APIM traces: `curl -sS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" "$APIM_BASE/apim/management/traces"`

## What Mapped Cleanly

- Request volume and latency visibility
- Gateway-centric observability
- Per-request debugging context

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial05.sh --setup
./docs/tutorials/apim-get-started/tutorial05.sh --verify
```

Use `--setup` to have [`tutorial05.sh`](tutorial05.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial05.sh --verify` output:

```text
Waiting for Grafana health at http://localhost:3001/api/health
Sending traced sample traffic
{
  "correlation_id": "tutorial05-health",
  "status_code": 200,
  "trace_id_present": true
}

{
  "correlation_id": "tutorial05-echo",
  "status_code": 200,
  "trace_id_present": true
}

Verifying observability surfaces
$ curl -sS "http://localhost:3001/api/health"
{
  "database": "ok"
}

$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/traces"
{
  "matching_traces": [
    {
      "correlation_id": "tutorial05-health",
      "status": 200,
      "upstream_url": "http://mock-backend:8080/api/health"
    },
    {
      "correlation_id": "tutorial05-echo",
      "status": 200,
      "upstream_url": "http://mock-backend:8080/api/echo"
    }
  ]
}
```

## Differences From Azure APIM

- This uses OTEL plus Grafana instead of Azure Monitor metrics, activity logs, and alert rules.
- There is no Azure resource-log pipeline or alert-group workflow in the simulator.
