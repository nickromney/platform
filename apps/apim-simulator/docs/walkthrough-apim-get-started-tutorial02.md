# APIM Simulator Walkthrough: Tutorial 02

Generated from a live run against the local repository.

Companion script: [tutorial02.sh](tutorials/apim-get-started/tutorial02.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial02.sh --setup
./docs/tutorials/apim-get-started/tutorial02.sh --verify

```

```output
Starting tutorial 02 stack with docker compose
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
{
  "id": "tutorial-product",
  "name": "Tutorial Product",
  "require_subscription": true,
  "subscription_count": 0
}

Attaching API 'tutorial-api' to product 'tutorial-product'
{
  "id": "tutorial-api",
  "path": "tutorial-api",
  "products": [
    "tutorial-product"
  ]
}

Creating subscription 'tutorial-sub'
{
  "id": "tutorial-sub",
  "name": "tutorial-sub",
  "primary_key": "tutorial-key",
  "products": [
    "tutorial-product"
  ]
}

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial02.sh --verify to validate product access.
Verifying product and subscription metadata
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/products/tutorial-product"
{
  "id": "tutorial-product",
  "require_subscription": true,
  "subscription_count": 1
}

$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/subscriptions/tutorial-sub"
{
  "id": "tutorial-sub",
  "primary_key": "tutorial-key",
  "products": [
    "tutorial-product"
  ],
  "state": "active"
}

Verifying subscription-backed access
$ curl -i "http://localhost:8000/tutorial-api/health"
{
  "detail": "Missing subscription key",
  "status_code": 401
}

$ curl -sS -H "Ocp-Apim-Subscription-Key: tutorial-key" "http://localhost:8000/tutorial-api/health"
{
  "path": "/api/health",
  "status": "ok"
}

```
