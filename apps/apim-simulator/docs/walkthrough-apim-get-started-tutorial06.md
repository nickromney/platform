# APIM Simulator Walkthrough: Tutorial 06

Generated from a live run against the local repository.

Companion script: [tutorial06.sh](tutorials/apim-get-started/tutorial06.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial06.sh --setup
./docs/tutorials/apim-get-started/tutorial06.sh --verify

```

```output
Starting tutorial 06 stack with docker compose
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

Creating product 'tutorial-product'
Attaching API 'tutorial-api' to product 'tutorial-product'
Creating subscription 'tutorial-sub'
Requesting a trace-enabled call
{
  "correlation_id": "tutorial06-health",
  "status_code": 200,
  "trace_id_present": true
}

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial06.sh --verify to validate the stored trace.
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
