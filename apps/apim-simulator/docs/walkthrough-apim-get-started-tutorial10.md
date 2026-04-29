# APIM Simulator Walkthrough: Tutorial 10

Generated from a live run against the local repository.

Companion script: [tutorial10.sh](tutorials/apim-get-started/tutorial10.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial10.sh --setup
./docs/tutorials/apim-get-started/tutorial10.sh --verify

```

```output
Starting tutorial 10 stack with docker compose
Compose files:
  - ./compose.yml
  - ./compose.public.yml
Running:
  docker compose \
    -f ./compose.yml \
    -f ./compose.public.yml \
    up --build -d
Waiting for gateway health at http://localhost:8000/apim/health
Importing OpenAPI source into API 'tutorial-api'
{
  "api_id": "tutorial-api",
  "path": "tutorial-api",
  "operations": [
    "echo",
    "health"
  ],
  "import": {
    "format": "openapi+json",
    "operation_count": 2,
    "upstream_base_url": "http://mock-backend:8080/api",
    "diagnostics": []
  }
}

REST Client example: ./docs/tutorials/apim-get-started/tutorial10.rest.http
Applying the REST Client policy update to 'tutorial-api'
{
  "contains_vscode_header": true,
  "scope_name": "tutorial-api",
  "scope_type": "api"
}

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial10.sh --verify to validate the authored policy.
Verifying the authored policy and gateway response
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/policies/api/tutorial-api"
{
  "contains_vscode_header": true,
  "scope_name": "tutorial-api",
  "scope_type": "api"
}

$ curl -i "http://localhost:8000/tutorial-api/health"
{
  "path": "/api/health",
  "status": "ok",
  "status_code": 200,
  "x_from_vscode": "true"
}

```
