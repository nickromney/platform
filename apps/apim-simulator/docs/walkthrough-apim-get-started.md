# APIM Simulator Walkthrough: APIM Get-Started Tutorial Mirror

*2026-04-15T17:55:04Z*

This walkthrough runs every mirrored tutorial script under `docs/tutorials/apim-get-started/` with both `--setup` and `--verify`. The scripts already emit the closest local equivalent to each Microsoft Learn step, so the captured outputs here are the most direct proof that the tutorial mirror still behaves as documented.

## Tutorial 01
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

## Tutorial 02
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

## Tutorial 03
Companion script: [tutorial03.sh](tutorials/apim-get-started/tutorial03.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial03.sh --setup
./docs/tutorials/apim-get-started/tutorial03.sh --verify

```

```output
Starting tutorial 03 stack with docker compose
Compose files:
  - ./compose.yml
  - ./compose.public.yml
Running:
  docker compose \
    -f ./compose.yml \
    -f ./compose.public.yml \
    up --build -d
Waiting for gateway health at http://localhost:8000/apim/health
Creating blank API 'mock-only'
{
  "id": "mock-only",
  "path": "mock-only",
  "upstream_base_url": "http://example.invalid"
}

Adding operation 'test-call' with an authored example response
{
  "example_name": "ok",
  "id": "test-call",
  "method": "GET",
  "url_template": "/test"
}

Enabling mock-response on 'mock-only:test-call'
{
  "contains_mock_response": true,
  "scope_name": "mock-only:test-call",
  "scope_type": "operation"
}

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial03.sh --verify to validate the mocked response.
Verifying mocked response
$ curl -sS "http://localhost:8000/mock-only/test"
{
  "sampleField": "test"
}

```

## Tutorial 04
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

## Tutorial 05
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

## Tutorial 06
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

## Tutorial 07
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

## Tutorial 08
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

## Tutorial 09
Companion script: [tutorial09.sh](tutorials/apim-get-started/tutorial09.sh)

```bash
set -euo pipefail
tutorial_cleanup_and_wait
./docs/tutorials/apim-get-started/tutorial09.sh --setup
./docs/tutorials/apim-get-started/tutorial09.sh --verify

```

```output
Starting tutorial 09 stack with docker compose
Compose files:
  - ./compose.yml
  - ./compose.public.yml
  - ./compose.ui.yml
Running:
  docker compose \
    -f ./compose.yml \
    -f ./compose.public.yml \
    -f ./compose.ui.yml \
    up -d
Waiting for gateway health at http://localhost:8000/apim/health
Waiting for operator console at http://localhost:3007
Operator console is available at http://localhost:3007
Gateway is available at http://localhost:8000

Setup complete. Run ./docs/tutorials/apim-get-started/tutorial09.sh --verify to validate the operator console.
Verifying the closest local equivalent
$ curl -sS -H "X-Apim-Tenant-Key: local-dev-tenant-key" "http://localhost:8000/apim/management/status"
{
  "gateway_scope": "gateway",
  "service_name": "apim-simulator"
}

$ curl -sS "http://localhost:3007"
{
  "status_code": 200
}

```

## Tutorial 10
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

## Tutorial 11
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
