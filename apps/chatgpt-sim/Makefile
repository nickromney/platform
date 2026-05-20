.PHONY: help test build update app-help app-test app-js-check app-build app-run-mcp app-run-shell up up-direct down logs ps compose-smoke compose-smoke-sso

COMPOSE_CMD ?= docker compose -f compose.yml
PLATFORM_DEMO_PASSWORD ?= local-dev-password
OAUTH2_PROXY_COOKIE_SECRET ?= 0123456789abcdef0123456789abcdef
SSO_COMPOSE_ENV := PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) CHATGPT_SIM_PUBLIC_PORT=18084 CHATGPT_SIM_APP_PORT=18085 CHATGPT_SIM_KEYCLOAK_PORT=8500

help:
	@echo "ChatGPT Sim:"
	@echo "  app-test       Run Go unit tests"
	@echo "  app-js-check   Run Biome and Deno checks for browser JavaScript"
	@echo "  app-build      Build the local app binary"
	@echo "  app-run-mcp    Run the MCP role directly"
	@echo "  app-run-shell  Run the shell role directly"
	@echo "  compose-smoke  Run the app-local compose smoke test"
	@echo "  compose-smoke-sso  Run the app-local SSO compose smoke test"
	@echo "  up             Start the app-local SSO compose stack"
	@echo "  up-direct      Start the direct app-local compose stack"
	@echo "  down           Stop the app-local compose stack"

app-help:
	@$(MAKE) --no-print-directory -C app help

app-test:
	@$(MAKE) --no-print-directory -C app test

app-js-check:
	@$(MAKE) --no-print-directory -C app js-check

app-build:
	@$(MAKE) --no-print-directory -C app build

app-run-mcp:
	@$(MAKE) --no-print-directory -C app run-mcp

app-run-shell:
	@$(MAKE) --no-print-directory -C app run-shell

test: app-test app-js-check compose-smoke compose-smoke-sso

build:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

update:
	@echo "chatgpt-sim has no dependency lock update workflow"

compose-smoke:
	@./tests/compose-smoke.sh --execute

compose-smoke-sso:
	@./tests/compose-smoke-sso.sh --execute

up:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE_CMD) --profile sso up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"
	@echo "Keycloak URL:    http://localhost:8500"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-direct:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"

down:
	@$(COMPOSE_CMD) down --remove-orphans

logs:
	@$(COMPOSE_CMD) logs -f

ps:
	@$(COMPOSE_CMD) ps
