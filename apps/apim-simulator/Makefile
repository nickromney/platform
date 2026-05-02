.DEFAULT_GOAL := help

COMPOSE ?= docker compose
STACK_SLOT_WIDTH ?= 100
PORT_OFFSET ?= 0
ifneq ($(strip $(STACK_SLOT)),)
PORT_OFFSET := $(shell expr $(STACK_SLOT) \* $(STACK_SLOT_WIDTH))
endif

calc_port = $(shell expr $(1) + $(PORT_OFFSET))
url_port_suffix = $(if $(filter 80 443,$(1)),,:$(1))
STACK_INSTANCE_SUFFIX := $(strip $(if $(STACK_SLOT),s$(STACK_SLOT),$(if $(filter-out 0,$(PORT_OFFSET)),o$(PORT_OFFSET),)))
compose_project_args = $(if $(STACK_INSTANCE_SUFFIX),--project-name apim-simulator-$(1)-$(STACK_INSTANCE_SUFFIX))
compose_stack = $(COMPOSE) $(call compose_project_args,$(1))

APIM_GATEWAY_PORT ?= $(call calc_port,8000)
GRAFANA_HOST ?= lgtm.apim.127.0.0.1.sslip.io
GRAFANA_PORT ?= $(call calc_port,8443)
OTEL_GRPC_PORT ?= $(call calc_port,4317)
OTEL_HTTP_PORT ?= $(call calc_port,4318)
KEYCLOAK_PORT ?= $(call calc_port,8180)
OPERATOR_CONSOLE_PORT ?= $(call calc_port,3007)
BACKSTAGE_ENABLED ?= false
BACKSTAGE_BUILD_ENABLED ?= true
BACKSTAGE_PORT ?= $(call calc_port,7007)
EDGE_HTTP_PORT ?= $(call calc_port,8088)
EDGE_TLS_HTTP_PORT ?= $(call calc_port,8080)
EDGE_TLS_PORT ?= $(call calc_port,9443)
TODO_FRONTEND_PORT ?= $(call calc_port,3000)
VITE_DEV_PORT ?= 5173
APIM_EDGE_ROOT_HOST ?= apim.127.0.0.1.sslip.io
APIM_EDGE_HOST ?= edge.apim.127.0.0.1.sslip.io
APIM_EDGE_WILDCARD_HOST ?= *.apim.127.0.0.1.sslip.io

APIM_BASE_URL ?= http://localhost:$(APIM_GATEWAY_PORT)
APIM_LOOPBACK_BASE_URL ?= http://127.0.0.1:$(APIM_GATEWAY_PORT)
GRAFANA_BASE_URL ?= https://$(GRAFANA_HOST)$(call url_port_suffix,$(GRAFANA_PORT))
KEYCLOAK_BASE_URL ?= http://localhost:$(KEYCLOAK_PORT)
OIDC_ISSUER_EXTERNAL ?= $(KEYCLOAK_BASE_URL)/realms/subnet-calculator
OPERATOR_CONSOLE_URL ?= http://localhost:$(OPERATOR_CONSOLE_PORT)
BACKSTAGE_BASE_URL ?= http://localhost:$(BACKSTAGE_PORT)
BACKSTAGE_IMAGE ?= apim-simulator-backstage:local
BACKSTAGE_BUILD_CONTEXT ?= ./backstage/app
BACKSTAGE_DOCKERFILE ?= Dockerfile
TODO_FRONTEND_BASE_URL ?= http://127.0.0.1:$(TODO_FRONTEND_PORT)
TODO_FRONTEND_BROWSER_URL ?= http://localhost:$(TODO_FRONTEND_PORT)
TODO_FRONTEND_ORIGIN_LOCALHOST ?= http://localhost:$(TODO_FRONTEND_PORT)
TODO_FRONTEND_ORIGIN_LOOPBACK ?= http://127.0.0.1:$(TODO_FRONTEND_PORT)
TODO_APIM_BASE_URL ?= $(APIM_LOOPBACK_BASE_URL)
TODO_APIM_PUBLIC_BASE_URL ?= $(APIM_BASE_URL)
TODO_GRAFANA_BASE_URL ?= $(GRAFANA_BASE_URL)
TODO_OBSERVABILITY_DASHBOARD_URL ?= $(GRAFANA_BASE_URL)/d/apim-simulator-overview/apim-simulator-overview
APIM_ALLOWED_ORIGIN_BROWSER_LOCALHOST ?= $(TODO_FRONTEND_ORIGIN_LOCALHOST)
APIM_ALLOWED_ORIGIN_OPERATOR_CONSOLE ?= $(OPERATOR_CONSOLE_URL)
APIM_ALLOWED_ORIGIN_VITE ?= http://localhost:$(VITE_DEV_PORT)
APIM_ALLOWED_ORIGIN_GATEWAY ?= $(APIM_BASE_URL)
EDGE_HTTP_BASE_URL ?= http://$(APIM_EDGE_HOST):$(EDGE_HTTP_PORT)
EDGE_TLS_BASE_URL ?= https://$(APIM_EDGE_HOST):$(EDGE_TLS_PORT)
SMOKE_HELLO_BASE_URL ?= $(APIM_LOOPBACK_BASE_URL)
SMOKE_HELLO_KEYCLOAK_BASE_URL ?= $(KEYCLOAK_BASE_URL)
SMOKE_OIDC_BASE_URL ?= $(APIM_LOOPBACK_BASE_URL)
SMOKE_OIDC_KEYCLOAK_BASE_URL ?= $(KEYCLOAK_BASE_URL)
SMOKE_MCP_URL ?= $(APIM_BASE_URL)/mcp
SMOKE_EDGE_BASE_URL ?= $(EDGE_HTTP_BASE_URL)
KEYVAULT_BASE_URL ?= $(APIM_LOOPBACK_BASE_URL)
PORTS ?= $(TODO_FRONTEND_PORT) $(GRAFANA_PORT) $(OTEL_GRPC_PORT) $(OTEL_HTTP_PORT) $(APIM_GATEWAY_PORT) $(EDGE_HTTP_PORT) $(EDGE_TLS_HTTP_PORT) $(EDGE_TLS_PORT) $(OPERATOR_CONSOLE_PORT) $(KEYCLOAK_PORT) $(if $(filter true,$(BACKSTAGE_ENABLED)),$(BACKSTAGE_PORT))
UP_ALL_SLOT_BASE ?= 0
UP_ALL_STACKS := up up-otel up-oidc up-mcp up-edge up-tls up-private up-ui up-hello up-hello-subscription up-hello-otel up-hello-oidc up-hello-oidc-subscription up-todo up-todo-otel

export STACK_SLOT STACK_SLOT_WIDTH PORT_OFFSET
export APIM_GATEWAY_PORT GRAFANA_PORT OTEL_GRPC_PORT OTEL_HTTP_PORT KEYCLOAK_PORT OPERATOR_CONSOLE_PORT BACKSTAGE_PORT EDGE_HTTP_PORT EDGE_TLS_HTTP_PORT EDGE_TLS_PORT TODO_FRONTEND_PORT VITE_DEV_PORT
export APIM_EDGE_ROOT_HOST APIM_EDGE_HOST APIM_EDGE_WILDCARD_HOST GRAFANA_HOST
export APIM_BASE_URL APIM_LOOPBACK_BASE_URL GRAFANA_BASE_URL KEYCLOAK_BASE_URL OIDC_ISSUER_EXTERNAL OPERATOR_CONSOLE_URL BACKSTAGE_BASE_URL BACKSTAGE_IMAGE BACKSTAGE_BUILD_CONTEXT BACKSTAGE_DOCKERFILE
export TODO_FRONTEND_BASE_URL TODO_FRONTEND_BROWSER_URL TODO_FRONTEND_ORIGIN_LOCALHOST TODO_FRONTEND_ORIGIN_LOOPBACK TODO_APIM_BASE_URL TODO_APIM_PUBLIC_BASE_URL TODO_GRAFANA_BASE_URL TODO_OBSERVABILITY_DASHBOARD_URL
export APIM_ALLOWED_ORIGIN_BROWSER_LOCALHOST APIM_ALLOWED_ORIGIN_OPERATOR_CONSOLE APIM_ALLOWED_ORIGIN_VITE APIM_ALLOWED_ORIGIN_GATEWAY
export EDGE_HTTP_BASE_URL EDGE_TLS_BASE_URL
export SMOKE_HELLO_BASE_URL SMOKE_HELLO_KEYCLOAK_BASE_URL SMOKE_OIDC_BASE_URL SMOKE_OIDC_KEYCLOAK_BASE_URL SMOKE_MCP_URL SMOKE_EDGE_BASE_URL
export KEYVAULT_BASE_URL

COMPOSE_BACKSTAGE_OVERLAY := $(if $(filter true,$(BACKSTAGE_ENABLED)),-f compose.backstage.yml --profile backstage)
COMPOSE_CORE := $(call compose_stack,core) -f compose.yml -f compose.public.yml $(COMPOSE_BACKSTAGE_OVERLAY)
COMPOSE_CORE_OTEL := $(call compose_stack,core-otel) -f compose.yml -f compose.public.yml -f compose.otel.yml
COMPOSE_OIDC := $(call compose_stack,oidc) -f compose.yml -f compose.public.yml -f compose.oidc.yml
COMPOSE_MCP := $(call compose_stack,mcp) -f compose.yml -f compose.public.yml -f compose.mcp.yml
COMPOSE_EDGE := $(call compose_stack,edge) -f compose.yml -f compose.edge.yml -f compose.mcp.yml
COMPOSE_TLS := $(call compose_stack,tls) -f compose.yml -f compose.edge.yml -f compose.tls.yml -f compose.mcp.yml
COMPOSE_PRIVATE := $(call compose_stack,private) -f compose.yml -f compose.private.yml -f compose.mcp.yml
COMPOSE_UI := $(call compose_stack,ui) -f compose.yml -f compose.public.yml -f compose.ui.yml
COMPOSE_HELLO := $(call compose_stack,hello) -f compose.yml -f compose.public.yml -f compose.hello.yml
COMPOSE_HELLO_OTEL := $(call compose_stack,hello-otel) -f compose.yml -f compose.public.yml -f compose.hello.yml -f compose.otel.yml -f compose.hello.otel.yml
COMPOSE_HELLO_OIDC := $(call compose_stack,hello-oidc) -f compose.yml -f compose.public.yml -f compose.oidc.yml -f compose.hello.yml
COMPOSE_TODO := $(call compose_stack,todo) -f compose.todo.yml
COMPOSE_TODO_OTEL := $(call compose_stack,todo-otel) -f compose.todo.yml -f compose.todo.otel.yml
COMPOSE_BACKSTAGE := $(call compose_stack,backstage) -f compose.yml -f compose.public.yml -f compose.backstage.yml --profile backstage
COMPOSE_KEYVAULT := $(call compose_stack,keyvault) -f compose.yml -f compose.public.yml -f compose.keyvault.yml
COMPOSE_ALL := $(call compose_stack,all) -f compose.yml -f compose.public.yml -f compose.edge.yml -f compose.tls.yml -f compose.private.yml -f compose.ui.yml -f compose.oidc.yml -f compose.mcp.yml
DEV_CERTS := examples/edge/certs/$(APIM_EDGE_HOST).crt examples/edge/certs/$(APIM_EDGE_HOST).key
HELP_FMT := "  %-34s %s\n"
UV_RUN := uv run --project $(CURDIR)
LINT_YAML_SCRIPT ?= scripts/lint-yaml.sh
LINT_MARKDOWN_SCRIPT ?= scripts/lint-markdown.sh
LINT_BASH32_SCRIPT ?= scripts/check-bash32-compat.sh
AUDIT_SHELL_SCRIPTS_SCRIPT ?= scripts/audit-shell-scripts.sh
CHECK_VERSION_SCRIPT ?= scripts/check-version.sh
RELEASE_SCRIPT ?= scripts/release.sh
RELEASE_TAG_SCRIPT ?= scripts/release_tag.sh

.PHONY: help prereqs check-docker-prerequisites check-mkcert-prerequisites ensure-certs install-hooks fmt lint lint-check lint-yaml lint-markdown lint-bash32 lint-shell frontend-check check-version update runtime-artifact release release-dry-run release-preview release-tag release-tag-dry-run build-backstage up up-all up-otel up-oidc up-mcp up-edge up-tls up-private up-ui up-backstage up-keyvault up-hello up-hello-subscription up-hello-otel up-hello-oidc up-hello-oidc-subscription up-todo up-todo-otel down down-all logs logs-otel logs-oidc logs-mcp logs-private logs-hello logs-hello-otel logs-hello-oidc logs-todo logs-todo-otel logs-backstage logs-keyvault test test-python test-shell compat compat-report import-tofu verify-azure verify-otel verify-hello-otel verify-todo-otel check-host-ports check-private-port-clear smoke-oidc smoke-mcp smoke-edge smoke-tls smoke-private smoke-hello smoke-todo smoke-backstage smoke-keyvault smoke-tutorials-live test-todo-e2e test-todo-bruno test-todo-postman export-todo-har compose-config compose-config-otel compose-config-oidc compose-config-mcp compose-config-edge compose-config-tls compose-config-private compose-config-ui compose-config-backstage compose-config-keyvault compose-config-hello compose-config-hello-otel compose-config-hello-oidc compose-config-todo compose-config-todo-otel

help:
	@printf "Run:\n"
	@printf "\nStack Lifecycle:\n"
	@printf $(HELP_FMT) "down" "Stop all compose services defined by this repo"
	@printf $(HELP_FMT) "up" "Start the direct public simulator stack"
	@printf $(HELP_FMT) "up-edge" "Start the edge HTTP MCP stack on $(APIM_EDGE_HOST):8088"
	@printf $(HELP_FMT) "up-hello" "Start the anonymous hello API example behind APIM"
	@printf $(HELP_FMT) "up-hello-oidc" "Start the JWT-only hello API example with Keycloak"
	@printf $(HELP_FMT) "up-hello-oidc-subscription" "Start the subscription-plus-JWT hello API example with Keycloak"
	@printf $(HELP_FMT) "up-hello-otel" "Start the hello API example with LGTM"
	@printf $(HELP_FMT) "up-hello-subscription" "Start the subscription-protected hello API example behind APIM"
	@printf $(HELP_FMT) "up-mcp" "Start the simulator with the MCP example overlay"
	@printf $(HELP_FMT) "up-oidc" "Start the simulator with the Keycloak overlay"
	@printf $(HELP_FMT) "up-otel" "Start the direct public simulator stack with LGTM at $(GRAFANA_BASE_URL)"
	@printf $(HELP_FMT) "up-private" "Start the private MCP stack without publishing the gateway host port"
	@printf $(HELP_FMT) "up-tls" "Start the edge TLS MCP stack on $(APIM_EDGE_HOST):9443"
	@printf $(HELP_FMT) "up-todo" "Start the Astro + APIM + FastAPI todo demo stack"
	@printf $(HELP_FMT) "up-todo-otel" "Start the todo demo stack with LGTM at $(GRAFANA_BASE_URL)"
	@printf $(HELP_FMT) "up-ui" "Start the operator console on localhost:3007"
	@printf $(HELP_FMT) "up-backstage" "Start the optional Backstage API catalog portal on $(BACKSTAGE_BASE_URL)"
	@printf $(HELP_FMT) "up-keyvault" "Start the direct public stack with local Key Vault persistence"
	@printf $(HELP_FMT) "BACKSTAGE_ENABLED=true make up" "Start the direct public stack with the Backstage overlay"
	@printf $(HELP_FMT) "up-all" "Start every compose stack at once using isolated slots"
	@printf $(HELP_FMT) "down-all" "Stop every stack launched by up-all"
	@printf "\nStack Isolation:\n"
	@printf $(HELP_FMT) "STACK_SLOT=1 make up-otel" "Shift published ports by a slot and isolate compose project names"
	@printf $(HELP_FMT) "PORT_OFFSET=100 make up-ui" "Shift published ports by a fixed offset without changing defaults"
	@printf "\nLogs:\n"
	@printf $(HELP_FMT) "logs" "Tail core stack logs"
	@printf $(HELP_FMT) "logs-hello" "Tail hello API example stack logs"
	@printf $(HELP_FMT) "logs-hello-oidc" "Tail hello API example logs with Keycloak"
	@printf $(HELP_FMT) "logs-hello-otel" "Tail hello API example logs with LGTM"
	@printf $(HELP_FMT) "logs-mcp" "Tail MCP stack logs"
	@printf $(HELP_FMT) "logs-oidc" "Tail OIDC stack logs"
	@printf $(HELP_FMT) "logs-otel" "Tail core stack logs with LGTM"
	@printf $(HELP_FMT) "logs-todo" "Tail todo demo stack logs"
	@printf $(HELP_FMT) "logs-todo-otel" "Tail todo demo stack logs with LGTM"
	@printf $(HELP_FMT) "logs-backstage" "Tail the optional Backstage portal stack logs"
	@printf $(HELP_FMT) "logs-keyvault" "Tail the Key Vault compose stack logs"
	@printf "\nCode Quality and Tooling:\n"
	@printf $(HELP_FMT) "check-version" "Check synchronized release versions and pinned upstream refs"
	@printf $(HELP_FMT) "check-host-ports" "Check common local host ports before starting stacks"
	@printf $(HELP_FMT) "prereqs" "Check Docker, mkcert, and local host ports before starting stacks"
	@printf $(HELP_FMT) "compat" "Run the curated APIM sample compatibility harness"
	@printf $(HELP_FMT) "compat-report" "Run static Terraform/APIM compatibility analysis (requires TOFU_SHOW=...)"
	@printf $(HELP_FMT) "fmt" "Format Python code with Ruff"
	@printf $(HELP_FMT) "frontend-check" "Run Biome, TypeScript, and Astro checks for repo frontends"
	@printf $(HELP_FMT) "import-tofu" "Import a tofu show JSON file into a running simulator (requires TOFU_SHOW=...)"
	@printf $(HELP_FMT) "install-hooks" "Enable the repo-managed git pre-commit hook"
	@printf $(HELP_FMT) "lint" "Run repo-level lint checks without modifying files"
	@printf $(HELP_FMT) "lint-bash32" "Check tracked shell scripts for Bash 3.2 compatibility"
	@printf $(HELP_FMT) "lint-check" "Check Python formatting and lint with Ruff without modifying files"
	@printf $(HELP_FMT) "lint-markdown" "Lint tracked Markdown files"
	@printf $(HELP_FMT) "lint-shell" "Audit executable shell script interfaces and hygiene"
	@printf $(HELP_FMT) "lint-yaml" "Lint tracked YAML files"
	@printf $(HELP_FMT) "test" "Run Python and shell tests"
	@printf $(HELP_FMT) "test-python" "Run the Python test suite"
	@printf $(HELP_FMT) "test-shell" "Run the shell script test suite with BATS"
	@printf $(HELP_FMT) "update" "Update uv, npm, and Backstage Yarn locks"
	@printf "\nVerification and Smoke:\n"
	@printf $(HELP_FMT) "export-todo-har" "Capture the todo APIM flow as a HAR file for Proxyman"
	@printf $(HELP_FMT) "smoke-edge" "Run the edge MCP and forwarded-header smoke test"
	@printf $(HELP_FMT) "smoke-hello" "Run the hello API smoke test (mode via SMOKE_HELLO_MODE)"
	@printf $(HELP_FMT) "smoke-mcp" "Run the end-to-end MCP smoke test against a running stack"
	@printf $(HELP_FMT) "smoke-oidc" "Run the end-to-end OIDC smoke test against a running stack"
	@printf $(HELP_FMT) "smoke-private" "Run the private-mode smoke test and internal probe"
	@printf $(HELP_FMT) "smoke-tls" "Run the TLS edge smoke test using the generated local CA"
	@printf $(HELP_FMT) "smoke-todo" "Run the APIM-backed todo demo smoke test"
	@printf $(HELP_FMT) "smoke-backstage" "Check optional Backstage health and catalog import"
	@printf $(HELP_FMT) "smoke-keyvault" "Run the local Key Vault secrets and certificates smoke test"
	@printf $(HELP_FMT) "smoke-tutorials-live" "Run all numbered tutorial scripts against live local stacks"
	@printf $(HELP_FMT) "test-todo-bruno" "Run the Bruno collection against the running todo demo stack"
	@printf $(HELP_FMT) "test-todo-e2e" "Run Playwright against the running todo demo stack"
	@printf $(HELP_FMT) "test-todo-postman" "Run the Postman collection against the running todo demo stack"
	@printf $(HELP_FMT) "verify-azure" "Diff curated requests against simulator and live Azure APIM"
	@printf $(HELP_FMT) "verify-hello-otel" "Verify OTEL signals for the LGTM-backed hello API starter"
	@printf $(HELP_FMT) "verify-otel" "Verify Grafana, Loki, Tempo, and Prometheus for the OTEL stack"
	@printf $(HELP_FMT) "verify-todo-otel" "Verify OTEL signals for the LGTM-backed todo demo stack"
	@printf "\nRelease:\n"
	@printf $(HELP_FMT) "runtime-artifact" "Build the narrow runtime source zip under dist/"
	@printf $(HELP_FMT) "release" "Bump to VERSION, run checks, and create a release commit"
	@printf $(HELP_FMT) "release-dry-run" "Preview the release-commit flow for VERSION without changing files"
	@printf $(HELP_FMT) "release-preview" "Alias for release-dry-run"
	@printf $(HELP_FMT) "release-tag" "Create an annotated vVERSION tag from the current main commit"
	@printf $(HELP_FMT) "release-tag-dry-run" "Preview tag creation for VERSION without changing git state"
	@printf "\nCompose Config:\n"
	@printf $(HELP_FMT) "compose-config" "Render docker compose config for the direct public stack"
	@printf $(HELP_FMT) "compose-config-edge" "Render docker compose config for the edge HTTP stack"
	@printf $(HELP_FMT) "compose-config-hello" "Render docker compose config for the hello API example"
	@printf $(HELP_FMT) "compose-config-hello-oidc" "Render docker compose config for the hello API example with Keycloak"
	@printf $(HELP_FMT) "compose-config-hello-otel" "Render docker compose config for the hello API example with LGTM"
	@printf $(HELP_FMT) "compose-config-mcp" "Render docker compose config for the MCP stack"
	@printf $(HELP_FMT) "compose-config-oidc" "Render docker compose config for the OIDC stack"
	@printf $(HELP_FMT) "compose-config-otel" "Render docker compose config for the direct public LGTM stack"
	@printf $(HELP_FMT) "compose-config-private" "Render docker compose config for the private MCP stack"
	@printf $(HELP_FMT) "compose-config-tls" "Render docker compose config for the edge TLS stack"
	@printf $(HELP_FMT) "compose-config-todo" "Render docker compose config for the todo demo stack"
	@printf $(HELP_FMT) "compose-config-todo-otel" "Render docker compose config for the todo demo LGTM stack"
	@printf $(HELP_FMT) "compose-config-ui" "Render docker compose config for the console stack"
	@printf $(HELP_FMT) "compose-config-backstage" "Render docker compose config for the Backstage portal overlay"
	@printf $(HELP_FMT) "compose-config-keyvault" "Render docker compose config for the Key Vault stack"

prereqs: check-docker-prerequisites check-mkcert-prerequisites check-host-ports

.PHONY: prereqs check-docker-prerequisites check-mkcert-prerequisites

check-docker-prerequisites:
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "docker is required but was not found in PATH." >&2; \
		exit 1; \
	fi
	@if ! docker compose version >/dev/null 2>&1; then \
		echo "'docker compose' is required but not available." >&2; \
		exit 1; \
	fi
	@if ! docker info >/dev/null 2>&1; then \
		echo "Docker is not running. Start Docker Desktop and try again." >&2; \
		exit 1; \
	fi

check-mkcert-prerequisites:
	@if ! command -v mkcert >/dev/null 2>&1; then \
		echo "mkcert is required but was not found in PATH." >&2; \
		echo "Install it, then run 'mkcert -install'." >&2; \
		exit 1; \
	fi
	@CAROOT="$$(mkcert -CAROOT 2>/dev/null || true)"; \
	if [ -z "$$CAROOT" ] || [ ! -f "$$CAROOT/rootCA.pem" ] || [ ! -f "$$CAROOT/rootCA-key.pem" ]; then \
		echo "mkcert is installed but its local CA is not ready." >&2; \
		echo "Run 'mkcert -install' and try again." >&2; \
		exit 1; \
	fi

ensure-certs: check-mkcert-prerequisites
	./scripts/gen_dev_certs.sh --execute

$(DEV_CERTS): check-mkcert-prerequisites
	./scripts/gen_dev_certs.sh --execute

build-backstage: check-docker-prerequisites
	@if [ "$(BACKSTAGE_BUILD_ENABLED)" != "true" ]; then \
		echo "Skipping Backstage image build because BACKSTAGE_BUILD_ENABLED=$(BACKSTAGE_BUILD_ENABLED)."; \
		exit 0; \
	fi
	@if [ ! -d "$(BACKSTAGE_BUILD_CONTEXT)" ]; then \
		echo "Backstage build context not found: $(BACKSTAGE_BUILD_CONTEXT)" >&2; \
		echo "Set BACKSTAGE_BUILD_CONTEXT to a compatible Backstage app, or set BACKSTAGE_BUILD_ENABLED=false and provide BACKSTAGE_IMAGE." >&2; \
		exit 1; \
	fi
	@if [ ! -f "$(BACKSTAGE_BUILD_CONTEXT)/$(BACKSTAGE_DOCKERFILE)" ]; then \
		echo "Backstage Dockerfile not found: $(BACKSTAGE_BUILD_CONTEXT)/$(BACKSTAGE_DOCKERFILE)" >&2; \
		exit 1; \
	fi
	$(COMPOSE_BACKSTAGE) build backstage

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

up-private:
	$(COMPOSE_PRIVATE) up --build -d

up-ui:
	$(COMPOSE_UI) up --build -d

up-backstage: build-backstage
	$(COMPOSE_BACKSTAGE) up --build -d

up-keyvault:
	$(COMPOSE_KEYVAULT) up --build -d

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

up-all:
	@set -e; \
	slot="$(UP_ALL_SLOT_BASE)"; \
	for target in $(UP_ALL_STACKS); do \
	  echo "==> $$target (STACK_SLOT=$$slot)"; \
	  ./scripts/run-stacked-make.sh --execute "$$slot" "$$target"; \
	  slot=$$((slot + 1)); \
	done

down:
	$(COMPOSE_CORE) down --remove-orphans
	$(COMPOSE_CORE_OTEL) down --remove-orphans
	$(COMPOSE_OIDC) down --remove-orphans
	$(COMPOSE_MCP) down --remove-orphans
	$(COMPOSE_EDGE) down --remove-orphans
	$(COMPOSE_TLS) down --remove-orphans
	$(COMPOSE_PRIVATE) down --remove-orphans
	$(COMPOSE_UI) down --remove-orphans
	$(COMPOSE_BACKSTAGE) down --remove-orphans
	$(COMPOSE_KEYVAULT) down --remove-orphans
	$(COMPOSE_HELLO) down --remove-orphans
	$(COMPOSE_HELLO_OTEL) down --remove-orphans
	$(COMPOSE_HELLO_OIDC) down --remove-orphans
	$(COMPOSE_TODO) down --remove-orphans
	$(COMPOSE_TODO_OTEL) down --remove-orphans

down-all:
	@set -e; \
	slot="$(UP_ALL_SLOT_BASE)"; \
	for _target in $(UP_ALL_STACKS); do \
	  echo "==> down (STACK_SLOT=$$slot)"; \
	  ./scripts/run-stacked-make.sh --execute "$$slot" down; \
	  slot=$$((slot + 1)); \
	done

logs:
	$(COMPOSE_CORE) logs -f apim-simulator mock-backend

logs-otel:
	$(COMPOSE_CORE_OTEL) logs -f apim-simulator mock-backend lgtm lgtm-proxy

logs-oidc:
	$(COMPOSE_OIDC) logs -f apim-simulator mock-backend keycloak

logs-mcp:
	$(COMPOSE_MCP) logs -f apim-simulator mcp-server

logs-private:
	$(COMPOSE_PRIVATE) logs -f apim-simulator mcp-server smoke-runner

logs-hello:
	$(COMPOSE_HELLO) logs -f apim-simulator hello-api

logs-hello-otel:
	$(COMPOSE_HELLO_OTEL) logs -f apim-simulator hello-api lgtm lgtm-proxy

logs-hello-oidc:
	$(COMPOSE_HELLO_OIDC) logs -f apim-simulator hello-api keycloak

logs-todo:
	$(COMPOSE_TODO) logs -f todo-frontend apim-simulator todo-api

logs-todo-otel:
	$(COMPOSE_TODO_OTEL) logs -f todo-frontend apim-simulator todo-api lgtm lgtm-proxy

logs-backstage:
	$(COMPOSE_BACKSTAGE) logs -f apim-simulator mock-backend backstage

logs-keyvault:
	$(COMPOSE_KEYVAULT) logs -f apim-simulator mock-backend

install-hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit

fmt:
	uv run --extra dev ruff format .

lint:
	@$(MAKE) --no-print-directory lint-check
	@$(MAKE) --no-print-directory lint-yaml
	@$(MAKE) --no-print-directory lint-markdown
	@$(MAKE) --no-print-directory lint-bash32
	@$(MAKE) --no-print-directory lint-shell

lint-check:
	uv run --extra dev ruff format --check .
	uv run --extra dev ruff check .

lint-yaml:
	@"$(LINT_YAML_SCRIPT)" --execute

lint-markdown:
	@"$(LINT_MARKDOWN_SCRIPT)" --execute

lint-bash32:
	@/bin/bash "$(LINT_BASH32_SCRIPT)" --execute

lint-shell:
	@"$(AUDIT_SHELL_SCRIPTS_SCRIPT)" --execute

frontend-check:
	npm --prefix ui ci
	npm --prefix ui run check
	npm --prefix examples/todo-app/frontend-astro ci
	npm --prefix examples/todo-app/frontend-astro run check

check-version:
	@"$(CHECK_VERSION_SCRIPT)" --execute

update:
	uv lock
	npm --prefix ui install --package-lock-only --ignore-scripts
	npm --prefix examples/todo-app/frontend-astro install --package-lock-only --ignore-scripts
	cd backstage/app && yarn install --mode=update-lockfile

check-host-ports:
	./scripts/check-host-ports.sh --execute $(PORTS)

runtime-artifact:
	$(UV_RUN) python scripts/build_runtime_artifact.py

release:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release VERSION=X.Y.Z"; exit 1; }
	@"$(RELEASE_SCRIPT)" --execute "$(VERSION)"

release-dry-run:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-dry-run VERSION=X.Y.Z"; exit 1; }
	@"$(RELEASE_SCRIPT)" --dry-run "$(VERSION)"

release-preview: release-dry-run

release-tag:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-tag VERSION=X.Y.Z"; exit 1; }
	@"$(RELEASE_TAG_SCRIPT)" --execute "$(VERSION)"

release-tag-dry-run:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-tag-dry-run VERSION=X.Y.Z"; exit 1; }
	@"$(RELEASE_TAG_SCRIPT)" --dry-run "$(VERSION)"

test: test-python test-shell

test-python:
	$(UV_RUN) --extra dev pytest -q --cov=app --cov-branch --cov-report=term-missing --cov-report=xml
	mkdir -p coverage-reports
	cp coverage.xml coverage-reports/python-coverage-report.xml

test-shell:
	@command -v bats >/dev/null 2>&1 || { echo "bats is required for shell tests"; exit 1; }
	bats tests/shell

compat:
	$(UV_RUN) python scripts/check_sample_compat.py

compat-report:
	$(UV_RUN) python scripts/compat_report.py

import-tofu:
	$(UV_RUN) python scripts/import_tofu.py

verify-azure:
	$(UV_RUN) python scripts/verify_azure.py

verify-otel:
	$(UV_RUN) python scripts/verify_otel.py

verify-hello-otel:
	$(UV_RUN) python scripts/verify_hello_otel.py

verify-todo-otel:
	VERIFY_OTEL_TODO=true $(UV_RUN) python scripts/verify_otel.py

smoke-oidc:
	$(UV_RUN) python scripts/smoke_oidc.py

smoke-mcp:
	SMOKE_MCP_URL="$(SMOKE_MCP_URL)" $(UV_RUN) --extra mcp python scripts/smoke_mcp.py

smoke-edge:
	SMOKE_EDGE_BASE_URL="$(SMOKE_EDGE_BASE_URL)" $(UV_RUN) --extra mcp python scripts/smoke_edge.py

smoke-tls:
	SMOKE_EDGE_BASE_URL="$(EDGE_TLS_BASE_URL)" $(UV_RUN) --extra mcp python scripts/smoke_edge.py

check-private-port-clear:
	$(UV_RUN) python -c "import socket; sock = socket.socket(); sock.settimeout(1); code = sock.connect_ex(('127.0.0.1', $(APIM_GATEWAY_PORT))); sock.close(); print('Host port $(APIM_GATEWAY_PORT) is unavailable, as required for private mode.') if code else (_ for _ in ()).throw(SystemExit('localhost:$(APIM_GATEWAY_PORT) is already reachable before private-mode launch; stop the conflicting listener before continuing'))"

smoke-private:
	$(MAKE) check-private-port-clear
	$(COMPOSE_PRIVATE) run --rm --entrypoint python3 smoke-runner scripts/run_smoke_private.py

smoke-hello:
	$(UV_RUN) python scripts/smoke_hello.py

smoke-todo:
	$(UV_RUN) python scripts/smoke_todo.py

smoke-backstage:
	BACKSTAGE_BASE_URL="$(BACKSTAGE_BASE_URL)" $(UV_RUN) python scripts/check_backstage.py

smoke-keyvault:
	KEYVAULT_BASE_URL="$(KEYVAULT_BASE_URL)" $(UV_RUN) python scripts/smoke_keyvault.py

smoke-tutorials-live:
	APIM_BASE="$(APIM_BASE_URL)" GRAFANA_BASE="$(GRAFANA_BASE_URL)" OPERATOR_CONSOLE_BASE="$(OPERATOR_CONSOLE_URL)" ./scripts/run_tutorial_smoke.sh --execute

test-todo-e2e:
	npm --prefix examples/todo-app/frontend-astro ci
	npm --prefix examples/todo-app/frontend-astro exec playwright install chromium
	BASE_URL="$(TODO_FRONTEND_BASE_URL)" API_BASE_URL="$(TODO_APIM_PUBLIC_BASE_URL)" GRAFANA_BASE_URL="$(TODO_GRAFANA_BASE_URL)" npm --prefix examples/todo-app/frontend-astro run test:e2e

test-todo-bruno:
	@tmp_env="$$(mktemp)"; \
	trap 'rm -f "$$tmp_env"' EXIT; \
	printf 'vars {\n  apimBaseUrl: %s\n  frontendOrigin: %s\n  subscriptionKey: todo-demo-key\n  invalidSubscriptionKey: bad-subscription-key\n}\n' "$(TODO_APIM_BASE_URL)" "$(TODO_FRONTEND_BASE_URL)" >"$$tmp_env" \
	&& cd examples/todo-app/api-clients/bruno \
	&& npm exec --yes --package=@usebruno/cli -- bru run --env-file "$$tmp_env" .

test-todo-postman:
	@tmp_env="$$(mktemp)"; \
	trap 'rm -f "$$tmp_env"' EXIT; \
	jq -n \
	  --arg apimBaseUrl "$(TODO_APIM_BASE_URL)" \
	  --arg frontendOrigin "$(TODO_FRONTEND_BASE_URL)" \
	  '{"id":"apim-simulator-local","name":"Local","values":[{"key":"apimBaseUrl","value":$$apimBaseUrl,"enabled":true},{"key":"frontendOrigin","value":$$frontendOrigin,"enabled":true},{"key":"subscriptionKey","value":"todo-demo-key","enabled":true},{"key":"invalidSubscriptionKey","value":"bad-subscription-key","enabled":true}]}' >"$$tmp_env" \
	&& npm exec --yes --package=newman -- newman run examples/todo-app/api-clients/postman/todo-through-apim.postman_collection.json --environment "$$tmp_env"

export-todo-har:
	TODO_HAR_APIM_BASE_URL="$(TODO_APIM_BASE_URL)" TODO_HAR_FRONTEND_BASE_URL="$(TODO_FRONTEND_BASE_URL)" $(UV_RUN) python scripts/export_todo_har.py

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

compose-config-backstage:
	$(COMPOSE_BACKSTAGE) config

compose-config-keyvault:
	$(COMPOSE_KEYVAULT) config

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
