# 10 - Manage APIs In Visual Studio Code

Source: [Tutorial: Manage APIs in Visual Studio Code](https://learn.microsoft.com/en-us/azure/api-management/visual-studio-code-tutorial)

Simulator status: Adapted

## Recommended Local Workflow

From the repo root:

```bash
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These examples assume `tutorial-api` already exists. If it does not, run step
1 first or use `./docs/tutorials/apim-get-started/tutorial01.sh --setup`.

Use Visual Studio Code with either:

- the built-in terminal and `curl`
- the checked-in REST Client example at [tutorial10.rest.http](tutorial10.rest.http)
- direct editing of the checked-in JSON config files in this repo

## Minimal REST Client Example

Open [tutorial10.rest.http](tutorial10.rest.http) in VS Code, or create a `.http` file like this:

```http
@base = http://localhost:8000
@tenant = local-dev-tenant-key

GET {{base}}/apim/management/apis
X-Apim-Tenant-Key: {{tenant}}

###

PUT {{base}}/apim/management/policies/api/tutorial-api
X-Apim-Tenant-Key: {{tenant}}
Content-Type: application/json

{
  "xml": "<policies><inbound /><backend /><outbound><set-header name=\"x-from-vscode\" exists-action=\"override\"><value>true</value></set-header></outbound><on-error /></policies>"
}
```

## What Mapped Cleanly

- local API CRUD
- policy editing
- direct request testing

## Shortcut

If you want the scripted shortcut instead of running the commands manually:

```bash
./docs/tutorials/apim-get-started/tutorial10.sh --setup
./docs/tutorials/apim-get-started/tutorial10.sh --verify
```

Use `--setup` to have [`tutorial10.sh`](tutorial10.sh) perform the local setup for this step. Use `--verify` to validate the existing tutorial state without restarting the stack.

Expected key `./docs/tutorials/apim-get-started/tutorial10.sh --verify` output:

```text
REST Client example: `docs/tutorials/apim-get-started/tutorial10.rest.http`
Applying the REST Client policy update to 'tutorial-api'
{
  "contains_vscode_header": true,
  "scope_name": "tutorial-api",
  "scope_type": "api"
}

Verifying the authored policy and gateway response
$ curl -i "http://localhost:8000/tutorial-api/health"
{
  "path": "/api/health",
  "status": "ok",
  "status_code": 200,
  "x_from_vscode": "true"
}
```

## Differences From Azure APIM

- This does not use the Azure API Management VS Code extension.
- The supported local equivalent is generic HTTP authoring against `/apim/management/...`.
