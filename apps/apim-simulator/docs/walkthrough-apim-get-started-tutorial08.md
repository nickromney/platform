# APIM Simulator Walkthrough: Tutorial 08

Generated from a live run against the local repository.

Companion script: [tutorial08.sh](tutorials/apim-get-started/tutorial08.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial08.sh --setup
./docs/tutorials/apim-get-started/tutorial08.sh --verify

```

```output
Starting tutorial 08 stack with docker compose
Compose files:
  - ./compose.yml
  - ./compose.public.yml
Running:
  docker compose \
    -f ./compose.yml \
    -f ./compose.public.yml \
    up --build -d
Waiting for gateway health at http://localhost:8000/apim/health
Creating version set 'public'
{
  "default_version": "v1",
  "id": "public",
  "version_header_name": "x-api-version",
  "versioning_scheme": "Header"
}

Creating versioned APIs
{
  "api_version": "v1",
  "id": "versioned-v1",
  "path": "versioned"
}

{
  "api_version": "v2",
  "id": "versioned-v2",
  "path": "versioned"
}

Added the echo operation to both versions

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial08.sh --verify to validate version routing.
Verifying version routing
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/api-version-sets/public"
{
  "default_version": "v1",
  "id": "public",
  "version_header_name": "x-api-version"
}

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
