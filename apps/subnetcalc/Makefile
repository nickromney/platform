USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build test update app-help app-test app-js-check app-build app-run-backend app-run-frontend up down urls logs ps compose-smoke
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
SUBNETCALC_LOCAL_PLATFORM ?= linux/arm64
else ifeq ($(HOST_ARCH),aarch64)
SUBNETCALC_LOCAL_PLATFORM ?= linux/arm64
else
SUBNETCALC_LOCAL_PLATFORM ?= linux/amd64
endif
ifeq ($(SUBNETCALC_LOCAL_PLATFORM),linux/arm64)
SUBNETCALC_GOARCH := arm64
else
SUBNETCALC_GOARCH := amd64
endif

DEFAULT_STACK_URL := http://localhost:8003
DEFAULT_API_HEALTH_URL := http://localhost:8090/api/v1/health
DEFAULT_COMPOSE_ENV := SUBNETCALC_LOCAL_PLATFORM=$(SUBNETCALC_LOCAL_PLATFORM)

export SUBNETCALC_LOCAL_PLATFORM

.PHONY: help prereqs build test update app-help app-test app-js-check app-build app-run-backend app-run-frontend up down urls logs ps compose-smoke

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

app-run-backend: ## Run the backend role directly on port 8090
	@$(MAKE) --no-print-directory -C app run-backend

app-run-frontend: ## Run the frontend role directly on port 8003
	@$(MAKE) --no-print-directory -C app run-frontend

##@ Build and test
build: prereqs ## Build the Go binary and compose image
	@GOARCH=$(SUBNETCALC_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) build subnetcalc-backend subnetcalc-frontend

test: app-test app-js-check compose-smoke ## Run Go tests, JS contract checks, and the local compose smoke test

compose-smoke: ## Run the Go-only compose smoke test
	@./tests/compose-smoke.sh --execute

update: ## No dependency locks are managed at this wrapper level
	@echo "subnetcalc: Go-only app; no package-manager locks to update"

##@ Run
up: prereqs ## Start the Go frontend and backend compose stack
	@GOARCH=$(SUBNETCALC_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) up -d --build subnetcalc-backend subnetcalc-frontend
	@$(MAKE) --no-print-directory urls

down: prereqs ## Stop the compose stack
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) down --remove-orphans

urls: ## Print local URLs
	@echo "Subnet Calculator URL: $(DEFAULT_STACK_URL)"
	@echo "API health:            $(DEFAULT_API_HEALTH_URL)"

logs: prereqs ## Tail compose logs
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) logs -f --tail=200

ps: prereqs ## Show compose container status
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) ps
