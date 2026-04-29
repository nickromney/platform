# APIM Simulator Walkthrough: Tutorial 09

Generated from a live run against the local repository.

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
