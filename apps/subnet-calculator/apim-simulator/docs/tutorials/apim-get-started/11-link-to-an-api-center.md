# 11 - Link To An API Center

Source: [Tutorial: Create or link an API Center to API Management](https://learn.microsoft.com/en-us/azure/api-management/tutorials/link-api-center)

Simulator status: Not appropriate

## Why This Does Not Map Directly

Azure API Center is a cloud inventory and governance product. `apim-simulator` is a local APIM-shaped gateway for development, testing, and policy iteration.

## Closest Local Equivalent

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

Export the simulator inventory so another cataloging tool can ingest it:

```bash
curl -sS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  "$APIM_BASE/apim/management/summary" > /tmp/apim-summary.json

curl -sS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  "$APIM_BASE/apim/management/apis" > /tmp/apim-apis.json
```

Those payloads give you:

- service metadata
- API inventory
- operations
- products
- version sets
- revisions and releases

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial11.sh --setup
./docs/tutorials/apim-get-started/tutorial11.sh --verify
```

Use `--setup` to have [`tutorial11.sh`](tutorial11.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial11.sh --verify` output:

```text
Exporting simulator inventory to /tmp/apim-simulator-tutorial11
Wrote /tmp/apim-simulator-tutorial11/summary.json
Wrote /tmp/apim-simulator-tutorial11/apis.json

Verifying exported inventory inputs
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/summary"
{
  "api_ids": [
    "default",
    "tutorial-api"
  ],
  "counts": {
    "api_releases": 1,
    "api_revisions": 2,
    "api_version_sets": 1,
    "apis": 2,
    "products": 2,
    "subscriptions": 1
  }
}

$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/apis"
{
  "api_ids": [
    "default",
    "tutorial-api"
  ],
  "paths": [
    "api",
    "tutorial-api"
  ]
}
```

## Guidance

If your goal is Azure-native API catalog synchronization, use real Azure APIM plus API Center.
If your goal is local API inventory and gateway rehearsal, use the simulator exports above.
