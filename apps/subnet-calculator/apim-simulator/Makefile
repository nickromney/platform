.DEFAULT_GOAL := help

COMPOSE ?= docker compose
COMPOSE_CORE := $(COMPOSE) -f compose.yml -f compose.public.yml
COMPOSE_CORE_OTEL := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.otel.yml
COMPOSE_OIDC := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.oidc.yml
COMPOSE_MCP := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.mcp.yml
COMPOSE_EDGE := $(COMPOSE) -f compose.yml -f compose.edge.yml -f compose.mcp.yml
COMPOSE_TLS := $(COMPOSE) -f compose.yml -f compose.edge.yml -f compose.tls.yml -f compose.mcp.yml
COMPOSE_PRIVATE := $(COMPOSE) -f compose.yml -f compose.private.yml -f compose.mcp.yml
COMPOSE_UI := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.ui.yml
COMPOSE_HELLO := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.hello.yml
COMPOSE_HELLO_OTEL := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.hello.yml -f compose.otel.yml -f compose.hello.otel.yml
COMPOSE_HELLO_OIDC := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.oidc.yml -f compose.hello.yml
COMPOSE_TODO := $(COMPOSE) -f compose.todo.yml
COMPOSE_TODO_OTEL := $(COMPOSE) -f compose.todo.yml -f compose.todo.otel.yml
COMPOSE_ALL := $(COMPOSE) -f compose.yml -f compose.public.yml -f compose.edge.yml -f compose.tls.yml -f compose.private.yml -f compose.ui.yml -f compose.oidc.yml -f compose.mcp.yml
DEV_CERTS := examples/edge/certs/apim.localtest.me.crt examples/edge/certs/apim.localtest.me.key

.PHONY: help ensure-certs install-hooks fmt lint lint-check frontend-check release release-dry-run release-tag release-tag-dry-run up up-otel up-oidc up-mcp up-edge up-tls up-ui up-hello up-hello-subscription up-hello-otel up-hello-oidc up-hello-oidc-subscription up-todo up-todo-otel down logs logs-otel logs-oidc logs-mcp logs-hello logs-hello-otel logs-hello-oidc logs-todo logs-todo-otel test test-python test-shell compat compat-report import-tofu verify-azure verify-otel verify-hello-otel verify-todo-otel check-private-port-clear smoke-oidc smoke-mcp smoke-edge smoke-tls smoke-private smoke-hello smoke-todo smoke-tutorials-live test-todo-e2e test-todo-bruno test-todo-postman export-todo-har compose-config compose-config-otel compose-config-oidc compose-config-mcp compose-config-edge compose-config-tls compose-config-private compose-config-ui compose-config-hello compose-config-hello-otel compose-config-hello-oidc compose-config-todo compose-config-todo-otel

help:
	@printf "Run:\n"
	@printf "  %-22s %s\n" "up" "Start the direct public simulator stack"
	@printf "  %-22s %s\n" "up-otel" "Start the direct public simulator stack with LGTM"
	@printf "  %-22s %s\n" "up-oidc" "Start the simulator with the Keycloak overlay"
	@printf "  %-22s %s\n" "up-mcp" "Start the simulator with the MCP example overlay"
	@printf "  %-22s %s\n" "up-edge" "Start the edge HTTP MCP stack on apim.localtest.me:8088"
	@printf "  %-22s %s\n" "up-tls" "Start the edge TLS MCP stack on apim.localtest.me:8443"
	@printf "  %-22s %s\n" "up-ui" "Start the operator console on localhost:3007"
	@printf "  %-22s %s\n" "up-hello" "Start the anonymous hello API example behind APIM"
	@printf "  %-22s %s\n" "up-hello-subscription" "Start the subscription-protected hello API example behind APIM"
	@printf "  %-22s %s\n" "up-hello-otel" "Start the hello API example with LGTM"
	@printf "  %-22s %s\n" "up-hello-oidc" "Start the JWT-only hello API example with Keycloak"
	@printf "  %-22s %s\n" "up-hello-oidc-subscription" "Start the subscription-plus-JWT hello API example with Keycloak"
	@printf "  %-22s %s\n" "up-todo" "Start the Astro + APIM + FastAPI todo demo stack"
	@printf "  %-22s %s\n" "up-todo-otel" "Start the todo demo stack with LGTM on localhost:3001"
	@printf "  %-22s %s\n" "down" "Stop all compose services defined by this repo"
	@printf "  %-22s %s\n" "logs" "Tail core stack logs"
	@printf "  %-22s %s\n" "logs-otel" "Tail core stack logs with LGTM"
	@printf "  %-22s %s\n" "logs-oidc" "Tail OIDC stack logs"
	@printf "  %-22s %s\n" "logs-mcp" "Tail MCP stack logs"
	@printf "  %-22s %s\n" "logs-hello" "Tail hello API example stack logs"
	@printf "  %-22s %s\n" "logs-hello-otel" "Tail hello API example logs with LGTM"
	@printf "  %-22s %s\n" "logs-hello-oidc" "Tail hello API example logs with Keycloak"
	@printf "  %-22s %s\n" "logs-todo" "Tail todo demo stack logs"
	@printf "  %-22s %s\n" "logs-todo-otel" "Tail todo demo stack logs with LGTM"
	@printf "  %-22s %s\n" "install-hooks" "Enable the repo-managed git pre-commit hook"
	@printf "  %-22s %s\n" "fmt" "Format Python code with Ruff"
	@printf "  %-22s %s\n" "lint" "Format Python code with Ruff and run lint checks"
	@printf "  %-22s %s\n" "lint-check" "Check Python formatting and lint with Ruff without modifying files"
	@printf "  %-22s %s\n" "frontend-check" "Run Biome, TypeScript, and Astro checks for repo frontends"
	@printf "  %-22s %s\n" "release" "Bump to VERSION, run checks, and create a release commit"
	@printf "  %-22s %s\n" "release-dry-run" "Preview the release-commit flow for VERSION without changing files"
	@printf "  %-22s %s\n" "release-tag" "Create an annotated vVERSION tag from the current main commit"
	@printf "  %-22s %s\n" "release-tag-dry-run" "Preview tag creation for VERSION without changing git state"
	@printf "  %-22s %s\n" "test" "Run Python and shell tests"
	@printf "  %-22s %s\n" "test-python" "Run the Python test suite"
	@printf "  %-22s %s\n" "test-shell" "Run the shell script test suite with BATS"
	@printf "  %-22s %s\n" "compat" "Run the curated APIM sample compatibility harness"
	@printf "  %-22s %s\n" "compat-report" "Run static Terraform/APIM compatibility analysis (requires TOFU_SHOW=...)"
	@printf "  %-22s %s\n" "import-tofu" "Import a tofu show JSON file into a running simulator (requires TOFU_SHOW=...)"
	@printf "  %-22s %s\n" "verify-azure" "Diff curated requests against simulator and live Azure APIM"
	@printf "  %-22s %s\n" "verify-otel" "Verify Grafana, Loki, Tempo, and Prometheus for the OTEL stack"
	@printf "  %-22s %s\n" "verify-hello-otel" "Verify OTEL signals for the LGTM-backed hello API starter"
	@printf "  %-22s %s\n" "verify-todo-otel" "Verify OTEL signals for the LGTM-backed todo demo stack"
	@printf "  %-22s %s\n" "smoke-oidc" "Run the end-to-end OIDC smoke test against a running stack"
	@printf "  %-22s %s\n" "smoke-mcp" "Run the end-to-end MCP smoke test against a running stack"
	@printf "  %-22s %s\n" "smoke-edge" "Run the edge MCP and forwarded-header smoke test"
	@printf "  %-22s %s\n" "smoke-tls" "Run the TLS edge smoke test using the generated local CA"
	@printf "  %-22s %s\n" "smoke-private" "Run the private-mode smoke test and internal probe"
	@printf "  %-22s %s\n" "smoke-hello" "Run the hello API smoke test (mode via SMOKE_HELLO_MODE)"
	@printf "  %-22s %s\n" "smoke-todo" "Run the APIM-backed todo demo smoke test"
	@printf "  %-22s %s\n" "smoke-tutorials-live" "Run all numbered tutorial scripts against live local stacks"
	@printf "  %-22s %s\n" "test-todo-e2e" "Run Playwright against the running todo demo stack"
	@printf "  %-22s %s\n" "test-todo-bruno" "Run the Bruno collection against the running todo demo stack"
	@printf "  %-22s %s\n" "test-todo-postman" "Run the Postman collection against the running todo demo stack"
	@printf "  %-22s %s\n" "export-todo-har" "Capture the todo APIM flow as a HAR file for Proxyman"
	@printf "  %-22s %s\n" "compose-config" "Render docker compose config for the direct public stack"
	@printf "  %-22s %s\n" "compose-config-otel" "Render docker compose config for the direct public LGTM stack"
	@printf "  %-22s %s\n" "compose-config-oidc" "Render docker compose config for the OIDC stack"
	@printf "  %-22s %s\n" "compose-config-mcp" "Render docker compose config for the MCP stack"
	@printf "  %-22s %s\n" "compose-config-edge" "Render docker compose config for the edge HTTP stack"
	@printf "  %-22s %s\n" "compose-config-tls" "Render docker compose config for the edge TLS stack"
	@printf "  %-22s %s\n" "compose-config-private" "Render docker compose config for the private MCP stack"
	@printf "  %-22s %s\n" "compose-config-ui" "Render docker compose config for the console stack"
	@printf "  %-22s %s\n" "compose-config-hello" "Render docker compose config for the hello API example"
	@printf "  %-22s %s\n" "compose-config-hello-otel" "Render docker compose config for the hello API example with LGTM"
	@printf "  %-22s %s\n" "compose-config-hello-oidc" "Render docker compose config for the hello API example with Keycloak"
	@printf "  %-22s %s\n" "compose-config-todo" "Render docker compose config for the todo demo stack"
	@printf "  %-22s %s\n" "compose-config-todo-otel" "Render docker compose config for the todo demo LGTM stack"

ensure-certs: $(DEV_CERTS)

$(DEV_CERTS):
	./scripts/gen_dev_certs.sh

up:
	$(COMPOSE_CORE) up --build -d

up-otel:
	$(COMPOSE_CORE_OTEL) up --build -d

up-oidc:
	$(COMPOSE_OIDC) up --build -d

up-mcp:
	$(COMPOSE_MCP) up --build -d

up-edge: ensure-certs
	$(COMPOSE_EDGE) up --build -d

up-tls: ensure-certs
	$(COMPOSE_TLS) up --build -d

up-ui:
	$(COMPOSE_UI) up -d

up-hello:
	$(COMPOSE_HELLO) up --build -d

up-hello-subscription:
	HELLO_APIM_CONFIG_PATH=/app/examples/hello-api/apim.subscription.json $(COMPOSE_HELLO) up --build -d

up-hello-otel:
	$(COMPOSE_HELLO_OTEL) up --build -d

up-hello-oidc:
	HELLO_APIM_CONFIG_PATH=/app/examples/hello-api/apim.oidc.jwt-only.json $(COMPOSE_HELLO_OIDC) up --build -d

up-hello-oidc-subscription:
	HELLO_APIM_CONFIG_PATH=/app/examples/hello-api/apim.oidc.subscription.json $(COMPOSE_HELLO_OIDC) up --build -d

up-todo:
	$(COMPOSE_TODO) up --build -d

up-todo-otel:
	$(COMPOSE_TODO_OTEL) up --build -d

down:
	$(COMPOSE_ALL) down --remove-orphans
	$(COMPOSE_CORE_OTEL) down --remove-orphans
	$(COMPOSE_HELLO) down --remove-orphans
	$(COMPOSE_HELLO_OTEL) down --remove-orphans
	$(COMPOSE_HELLO_OIDC) down --remove-orphans
	$(COMPOSE_TODO) down --remove-orphans
	$(COMPOSE_TODO_OTEL) down --remove-orphans

logs:
	$(COMPOSE_CORE) logs -f apim-simulator mock-backend

logs-otel:
	$(COMPOSE_CORE_OTEL) logs -f apim-simulator mock-backend lgtm

logs-oidc:
	$(COMPOSE_OIDC) logs -f apim-simulator mock-backend keycloak

logs-mcp:
	$(COMPOSE_MCP) logs -f apim-simulator mcp-server

logs-hello:
	$(COMPOSE_HELLO) logs -f apim-simulator hello-api

logs-hello-otel:
	$(COMPOSE_HELLO_OTEL) logs -f apim-simulator hello-api lgtm

logs-hello-oidc:
	$(COMPOSE_HELLO_OIDC) logs -f apim-simulator hello-api keycloak

logs-todo:
	$(COMPOSE_TODO) logs -f todo-frontend apim-simulator todo-api

logs-todo-otel:
	$(COMPOSE_TODO_OTEL) logs -f todo-frontend apim-simulator todo-api lgtm

install-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit

fmt:
	uv run --extra dev ruff format .

lint:
	uv run --extra dev ruff format .
	uv run --extra dev ruff check .

lint-check:
	uv run --extra dev ruff format --check .
	uv run --extra dev ruff check .

frontend-check:
	npm --prefix ui ci
	npm --prefix ui run check
	npm --prefix examples/todo-app/frontend-astro ci
	npm --prefix examples/todo-app/frontend-astro run check

release:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release VERSION=0.2.0"; exit 1; }
	./scripts/release.sh "$(VERSION)"

release-dry-run:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-dry-run VERSION=0.2.0"; exit 1; }
	DRY_RUN=1 ./scripts/release.sh "$(VERSION)"

release-tag:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-tag VERSION=0.2.0"; exit 1; }
	./scripts/release_tag.sh "$(VERSION)"

release-tag-dry-run:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-tag-dry-run VERSION=0.2.0"; exit 1; }
	DRY_RUN=1 ./scripts/release_tag.sh "$(VERSION)"

test: test-python test-shell

test-python:
	uv run --extra dev pytest -q

test-shell:
	@command -v bats >/dev/null 2>&1 || { echo "bats is required for shell tests"; exit 1; }
	bats tests/shell

compat:
	uv run python scripts/check_sample_compat.py

compat-report:
	uv run python scripts/compat_report.py

import-tofu:
	uv run python scripts/import_tofu.py

verify-azure:
	uv run python scripts/verify_azure.py

verify-otel:
	uv run python scripts/verify_otel.py

verify-hello-otel:
	uv run python scripts/verify_hello_otel.py

verify-todo-otel:
	VERIFY_OTEL_TODO=true uv run python scripts/verify_otel.py

smoke-oidc:
	uv run python scripts/smoke_oidc.py

smoke-mcp:
	uv run --with mcp python scripts/smoke_mcp.py

smoke-edge:
	uv run --with mcp python scripts/smoke_edge.py

smoke-tls:
	SMOKE_EDGE_BASE_URL=https://apim.localtest.me:8443 uv run --with mcp python scripts/smoke_edge.py

check-private-port-clear:
	uv run python -c "import socket; sock = socket.socket(); sock.settimeout(1); code = sock.connect_ex(('127.0.0.1', 8000)); sock.close(); print('Host port 8000 is unavailable, as required for private mode.') if code else (_ for _ in ()).throw(SystemExit('localhost:8000 is already reachable before private-mode launch; stop the conflicting listener before continuing'))"

smoke-private:
	$(MAKE) check-private-port-clear
	$(COMPOSE_PRIVATE) run --rm --entrypoint python3 smoke-runner scripts/run_smoke_private.py

smoke-hello:
	uv run python scripts/smoke_hello.py

smoke-todo:
	uv run python scripts/smoke_todo.py

smoke-tutorials-live:
	./scripts/run_tutorial_smoke.sh

test-todo-e2e:
	npm --prefix examples/todo-app/frontend-astro ci
	npm --prefix examples/todo-app/frontend-astro exec playwright install chromium
	npm --prefix examples/todo-app/frontend-astro run test:e2e

test-todo-bruno:
	cd examples/todo-app/api-clients/bruno && npm exec --yes --package=@usebruno/cli -- bru run --env-file ./environments/local.bru .

test-todo-postman:
	npm exec --yes --package=newman -- newman run examples/todo-app/api-clients/postman/todo-through-apim.postman_collection.json --environment examples/todo-app/api-clients/postman/local.postman_environment.json

export-todo-har:
	uv run python scripts/export_todo_har.py

compose-config:
	$(COMPOSE_CORE) config

compose-config-otel:
	$(COMPOSE_CORE_OTEL) config

compose-config-oidc:
	$(COMPOSE_OIDC) config

compose-config-mcp:
	$(COMPOSE_MCP) config

compose-config-edge:
	$(COMPOSE_EDGE) config

compose-config-tls:
	$(COMPOSE_TLS) config

compose-config-private:
	$(COMPOSE_PRIVATE) config

compose-config-ui:
	$(COMPOSE_UI) config

compose-config-hello:
	$(COMPOSE_HELLO) config

compose-config-hello-otel:
	$(COMPOSE_HELLO_OTEL) config

compose-config-hello-oidc:
	$(COMPOSE_HELLO_OIDC) config

compose-config-todo:
	$(COMPOSE_TODO) config

compose-config-todo-otel:
	$(COMPOSE_TODO_OTEL) config
