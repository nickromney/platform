USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs test build update app-help app-test app-build app-run up down logs ps compose-smoke
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example

export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE

.PHONY: help prereqs test build update app-help app-test app-build app-run up down logs ps compose-smoke

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

app-build: ## Build the local app binary
	@$(MAKE) --no-print-directory -C app build

app-run: ## Run the API directly
	@$(MAKE) --no-print-directory -C app run

##@ Build and test
test: app-test compose-smoke ## Run Go tests and the app-local compose smoke test

build: prereqs ## Build the Go binary and compose image
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

compose-smoke: ## Run the app-local compose smoke test
	@./tests/compose-smoke.sh --execute

update: ## No dependency locks are managed at this wrapper level
	@echo "idp-core: Go-only app; no package-manager locks to update"

##@ Run
up: prereqs ## Start the app-local compose stack
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "IDP Core URL: http://localhost:18086"

down: prereqs ## Stop the app-local compose stack
	@$(COMPOSE_CMD) down --remove-orphans

logs: prereqs ## Tail compose logs
	@$(COMPOSE_CMD) logs -f --tail=200

ps: prereqs ## Show compose container status
	@$(COMPOSE_CMD) ps
