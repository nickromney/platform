# APIM Simulator Walkthrough: Tutorial 07

Generated from a live run against the local repository.

Companion script: [tutorial07.sh](tutorials/apim-get-started/tutorial07.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial07.sh --setup
./docs/tutorials/apim-get-started/tutorial07.sh --verify

```

```output
Starting tutorial 07 stack with docker compose
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

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial07.sh --verify to validate the revision metadata.
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

$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/apis/tutorial-api/revisions"
{
  "revisions": [
    {
      "id": "1",
      "is_current": false
    },
    {
      "id": "2",
      "is_current": true
    }
  ]
}

$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/apis/tutorial-api/releases"
{
  "releases": [
    {
      "id": "public",
      "revision": "2"
    }
  ]
}

```
