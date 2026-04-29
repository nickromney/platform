# APIM Simulator Walkthrough: Tutorial 11

Generated from a live run against the local repository.

Companion script: [tutorial11.sh](tutorials/apim-get-started/tutorial11.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial11.sh --setup
./docs/tutorials/apim-get-started/tutorial11.sh --verify

```

```output
Starting tutorial 11 stack with docker compose
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

Creating inventory that is worth exporting
Exporting simulator inventory to /tmp/apim-simulator-tutorial11
Wrote /tmp/apim-simulator-tutorial11/summary.json
Wrote /tmp/apim-simulator-tutorial11/apis.json

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial11.sh --verify to validate the exported inventory inputs.
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
