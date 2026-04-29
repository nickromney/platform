# APIM Simulator Walkthrough: Tutorial 04

Generated from a live run against the local repository.

Companion script: [tutorial04.sh](tutorials/apim-get-started/tutorial04.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial04.sh --setup
./docs/tutorials/apim-get-started/tutorial04.sh --verify

```

```output
Starting tutorial 04 stack with docker compose
Compose files:
  - ./compose.yml
  - ./compose.public.yml
Running:
  docker compose \
    -f ./compose.yml \
    -f ./compose.public.yml \
    up --build -d --force-recreate apim-simulator mock-backend
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
Applying transform and rate-limit policy to 'tutorial-api'
{
  "contains_custom_header": true,
  "contains_rate_limit": true,
  "scope_name": "tutorial-api",
  "scope_type": "api"
}

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial04.sh --verify to validate the policy behaviour.
Verifying transform and throttling
$ curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "http://localhost:8000/tutorial-api/health"
{
  "custom_header": "My custom value",
  "path": "/api/health",
  "status": "ok",
  "status_code": 200
}

$ curl -i -H "Ocp-Apim-Subscription-Key: tutorial-key" "http://localhost:8000/tutorial-api/health"
{
  "body_text": "Rate limit exceeded",
  "retry_after_present": true,
  "status_code": 429
}

```
