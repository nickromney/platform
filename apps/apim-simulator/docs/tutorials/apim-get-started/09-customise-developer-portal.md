# 9 - Customise Developer Portal

Source: [Tutorial: Access and customise the developer portal](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-developer-portal-customize)

Simulator status: Not appropriate

## Why This Does Not Map Directly

The Microsoft developer portal is a managed CMS and public API-consumer website. `apim-simulator` is a local gateway and operator tool, not a CMS clone.

## Closest Local Equivalent

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

Use the operator console instead:

```bash
make up-ui
```

Open:

- gateway: `http://localhost:8000`
- operator console: `http://localhost:3007`

The operator console is the supported local surface for:

- policy editing
- trace browsing
- replaying requests
- inspecting and rotating subscriptions

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial09.sh --setup
./docs/tutorials/apim-get-started/tutorial09.sh --verify
```

Use `--setup` to have [`tutorial09.sh`](tutorial09.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial09.sh --verify` output:

```text
Verifying the closest local equivalent
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/status"
{
  "gateway_scope": "gateway",
  "service_name": "apim-simulator"
}

$ curl -sS "http://localhost:3007"
{
  "status_code": 200
}
```

## Guidance

If you need to rehearse developer-portal workflows, use real Azure APIM.
If you need to rehearse gateway behaviour, policies, traces, and management edits locally, stay in the simulator.
