# APIM Simulator Walkthrough: Tutorial 05

Generated from a live run against the local repository.

Companion script: [tutorial05.sh](tutorials/apim-get-started/tutorial05.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial05.sh --setup
./docs/tutorials/apim-get-started/tutorial05.sh --verify

```

```output
Starting tutorial 05 stack with docker compose
Compose files:
  - ./compose.yml
  - ./compose.public.yml
  - ./compose.otel.yml
Running:
  docker compose \
    -f ./compose.yml \
    -f ./compose.public.yml \
    -f ./compose.otel.yml \
    up --build -d
Waiting for gateway health at http://localhost:8000/apim/health
Waiting for Grafana health at https://lgtm.apim.127.0.0.1.sslip.io:8443/api/health
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

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial05.sh --verify to validate the observability surfaces.
Verifying observability surfaces
$ curl -sS "https://lgtm.apim.127.0.0.1.sslip.io:8443/api/health"
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
