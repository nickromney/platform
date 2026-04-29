# 3 - Mock API Responses

Source: [Tutorial: Mock API responses](https://learn.microsoft.com/en-us/azure/api-management/mock-api-responses)

Simulator status: Supported

## Run It Locally

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

Create a blank API with a placeholder backend:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/mock-only" \
  --data '{"name":"Mock Only","path":"mock-only","upstream_base_url":"http://example.invalid"}'
```

Add an operation with an authored example response:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/apis/mock-only/operations/test-call" \
  --data '{"name":"Test call","method":"GET","url_template":"/test","responses":[{"status_code":200,"representations":[{"content_type":"application/json","examples":[{"name":"ok","value":{"sampleField":"test"}}]}]}]}'
```

Enable native `mock-response` on the operation:

```bash
curl -sS -X PUT -H "X-Apim-Tenant-Key: $APIM_TENANT_KEY" \
  -H "Content-Type: application/json" \
  "$APIM_BASE/apim/management/policies/operation/mock-only:test-call" \
  --data '{"xml":"<policies><inbound><mock-response status-code=\"200\" content-type=\"application/json\" /></inbound><backend /><outbound /><on-error /></policies>"}'
```

Test the mocked API:

```bash
curl -sS "$APIM_BASE/mock-only/test"
```

## What Mapped Cleanly

- Blank API creation
- Manual operation authoring
- `mock-response` policy execution without reaching a backend

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial03.sh --setup
./docs/tutorials/apim-get-started/tutorial03.sh --verify
```

Use `--setup` to have [`tutorial03.sh`](tutorial03.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial03.sh --verify` output:

```text
Creating blank API 'mock-only'
{
  "id": "mock-only",
  "path": "mock-only",
  "upstream_base_url": "http://example.invalid"
}

Adding operation 'test-call' with an authored example response
{
  "example_name": "ok",
  "id": "test-call",
  "method": "GET",
  "url_template": "/test"
}

Enabling mock-response on 'mock-only:test-call'
{
  "contains_mock_response": true,
  "scope_name": "mock-only:test-call",
  "scope_type": "operation"
}

Verifying mocked response
$ curl -sS "http://localhost:8000/mock-only/test"
{
  "sampleField": "test"
}
```

## Differences From Azure APIM

- The simulator returns the first matching authored response example for the current operation.
- It does not attempt full schema-driven sample synthesis.
