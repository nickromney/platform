# APIM Simulator Walkthrough: Tutorial 01

Generated from a live run against the local repository.

Companion script: [tutorial01.sh](tutorials/apim-get-started/tutorial01.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial01.sh --setup
./docs/tutorials/apim-get-started/tutorial01.sh --verify

```

```output
host port 8000 still busy after 30s; retrying make down once
Starting tutorial 01 stack with docker compose
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

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial01.sh --verify to validate the imported API.
Verifying imported API metadata
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/apis/tutorial-api"
{
  "id": "tutorial-api",
  "operations": [
    "echo",
    "health"
  ],
  "path": "tutorial-api",
  "upstream_base_url": "http://mock-backend:8080/api"
}

Verifying imported API routes
$ curl -sS "http://localhost:8000/tutorial-api/health"
{
  "path": "/api/health",
  "status": "ok"
}

$ curl -sS "http://localhost:8000/tutorial-api/echo"
{
  "body": "",
  "method": "GET",
  "ok": true,
  "path": "/api/echo"
}

```
