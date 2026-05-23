USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs test build update app-help app-test app-js-check app-build app-run-mcp app-run-shell up up-direct down logs ps compose-smoke compose-smoke-sso
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
PLATFORM_DEMO_PASSWORD ?= local-dev-password
OAUTH2_PROXY_COOKIE_SECRET ?= 0123456789abcdef0123456789abcdef
SSO_COMPOSE_ENV := PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) CHATGPT_SIM_PUBLIC_PORT=18084 CHATGPT_SIM_APP_PORT=18085 CHATGPT_SIM_KEYCLOAK_PORT=8500

export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_DEMO_PASSWORD
export OAUTH2_PROXY_COOKIE_SECRET

.PHONY: help prereqs test build update app-help app-test app-js-check app-build app-run-mcp app-run-shell up up-direct down logs ps compose-smoke compose-smoke-sso

##@ Prerequisites
prereqs: ## Check local compose prerequisites
	@$(MAKE) --no-print-directory check-platform-env
	@if [ -n "$(COMPOSE_CMD)" ]; then \
		echo "✓ $(COMPOSE_CMD) found"; \
	else \
		echo "✗ No supported compose backend found"; \
		"$(abspath ../../scripts/install-tool-hints.sh)" --execute --plain docker podman podman-compose | sed 's/^/    /'; \
		exit 1; \
	fi

##@ App
app-help: ## Show app Makefile targets
	@$(MAKE) --no-print-directory -C app help

app-test: ## Run Go unit tests
	@$(MAKE) --no-print-directory -C app test

app-js-check: ## Check vanilla JavaScript source contracts
	@$(MAKE) --no-print-directory -C app js-check

app-build: ## Build the local app binary
	@$(MAKE) --no-print-directory -C app build

app-run-mcp: ## Run the MCP role directly
	@$(MAKE) --no-print-directory -C app run-mcp

app-run-shell: ## Run the shell role directly
	@$(MAKE) --no-print-directory -C app run-shell

##@ Build and test
test: app-test app-js-check compose-smoke compose-smoke-sso ## Run Go tests, JS checks, and direct and SSO compose smoke tests

build: prereqs ## Build the Go binary and compose image
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

compose-smoke: ## Run the app-local compose smoke test
	@./tests/compose-smoke.sh --execute

compose-smoke-sso: ## Run the app-local SSO compose smoke test
	@./tests/compose-smoke-sso.sh --execute

update: ## No dependency locks are managed at this wrapper level
	@echo "chatgpt-sim: Go-only app; no package-manager locks to update"

##@ Run
up: prereqs ## Start the app-local SSO compose stack
	@$(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE_CMD) --profile sso up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"
	@echo "Keycloak URL:    http://localhost:8500"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-direct: prereqs ## Start the direct app-local compose stack
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"

down: prereqs ## Stop the app-local compose stack
	@$(COMPOSE_CMD) down --remove-orphans

logs: prereqs ## Tail compose logs
	@$(COMPOSE_CMD) logs -f --tail=200

ps: prereqs ## Show compose container status
	@$(COMPOSE_CMD) ps
