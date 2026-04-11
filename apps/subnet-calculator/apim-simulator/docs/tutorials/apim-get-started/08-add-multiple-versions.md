# 8 - Add Multiple Versions

Source: [Tutorial: Add multiple versions](https://learn.microsoft.com/en-us/azure/api-management/api-management-get-started-publish-versions)

Simulator status: Supported

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

Create a version set:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/api-version-sets/public" \
  --data '{"display_name":"Public","versioning_scheme":"Header","version_header_name":"x-api-version","default_version":"v1"}'
```

Create two APIs that share the same public path but declare different versions:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/versioned-v1" \
  --data '{"name":"Versioned V1","path":"versioned","upstream_base_url":"http://mock-backend:8080/api","api_version_set":"public","api_version":"v1"}'

curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/versioned-v2" \
  --data '{"name":"Versioned V2","path":"versioned","upstream_base_url":"http://mock-backend:8080/api","api_version_set":"public","api_version":"v2","policies_xml":"<policies><inbound /><backend /><outbound><set-header name=\"x-version\" exists-action=\"override\"><value>v2</value></set-header></outbound><on-error /></policies>"}'
```

Add the same operation to both:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/versioned-v1/operations/echo" \
  --data '{"name":"echo","method":"GET","url_template":"/echo"}'

curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/versioned-v2/operations/echo" \
  --data '{"name":"echo","method":"GET","url_template":"/echo"}'
```

Verify version routing:

```bash
curl -i -H "x-api-version: v1" "$APIM_BASE/versioned/echo"
curl -i -H "x-api-version: v2" "$APIM_BASE/versioned/echo"
```

## What Mapped Cleanly

- Version-set CRUD
- header, query-string, and segment versioning schemes
- version-based route selection

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial08.sh --setup
./docs/tutorials/apim-get-started/tutorial08.sh --verify
```

Use `--setup` to have [`tutorial08.sh`](tutorial08.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial08.sh --verify` output:

```text
Creating version set 'public'
{
  "default_version": "v1",
  "id": "public",
  "version_header_name": "x-api-version",
  "versioning_scheme": "Header"
}

Verifying version routing
$ curl -i -H "x-api-version: v1" "http://localhost:8000/versioned/echo"
{
  "path": "/api/echo",
  "status_code": 200,
  "x_version": null
}

$ curl -i -H "x-api-version: v2" "http://localhost:8000/versioned/echo"
{
  "path": "/api/echo",
  "status_code": 200,
  "x_version": "v2"
}
```

## Differences From Azure APIM

- There is no developer portal version picker.
- Version management is exercised through the simulator management API.
