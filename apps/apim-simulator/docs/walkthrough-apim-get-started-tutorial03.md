# APIM Simulator Walkthrough: Tutorial 03

Generated from a live run against the local repository.

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
