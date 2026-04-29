# 7 - Add Revisions

Source: [Tutorial: Use revisions](https://learn.microsoft.com/en-us/azure/api-management/api-management-get-started-revise-api)

Simulator status: Partial

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These commands assume `tutorial-api` already exists. If it does not, run step
1 first or use `./docs/tutorials/apim-get-started/tutorial01.sh --setup`.

Add revision metadata:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/tutorial-api/revisions/1" \
  --data '{"description":"Initial revision","is_current":false,"is_online":false}'

curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/tutorial-api/revisions/2" \
  --data '{"description":"Current revision","is_current":true,"is_online":true,"source_api_id":"service/apim-simulator/apis/tutorial-api;rev=1"}'
```

Create a release for the current revision:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/tutorial-api/releases/public" \
  --data '{"notes":"Published revision","revision":"2"}'
```

Inspect the results:

```bash
curl -sS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  "$APIM_BASE/apim/management/apis/tutorial-api/revisions"

curl -sS -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  "$APIM_BASE/apim/management/apis/tutorial-api/releases"
```

## What Mapped Cleanly

- Revision metadata
- current-revision bookkeeping
- release metadata

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial07.sh --setup
./docs/tutorials/apim-get-started/tutorial07.sh --verify
```

Use `--setup` to have [`tutorial07.sh`](tutorial07.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial07.sh --verify` output:

```text
Adding revision metadata
{
  "description": "Initial revision",
  "id": "1",
  "is_current": false,
  "is_online": false
}

{
  "description": "Current revision",
  "id": "2",
  "is_current": true,
  "source_api_id": "service/apim-simulator/apis/tutorial-api;rev=1"
}

Creating release 'public'
{
  "api_id": "service/apim-simulator/apis/tutorial-api;rev=2",
  "id": "public",
  "revision": "2"
}

Verifying revision metadata
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/apis/tutorial-api"
{
  "id": "tutorial-api",
  "release_ids": [
    "public"
  ],
  "revision": "2",
  "revision_ids": [
    "1",
    "2"
  ]
}
```

## Differences From Azure APIM

- Revisions are descriptive in the simulator.
- Multiple Azure revisions still collapse into one active local runtime API.
- Revision-specific `;rev=` routing is not modeled as a separate runtime surface.
