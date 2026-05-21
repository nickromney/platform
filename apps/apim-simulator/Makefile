USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build test update app-help app-test app-js-check app-build app-run up up-direct down urls logs ps compose-smoke compose-smoke-sso
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
APIM_LOCAL_PLATFORM ?= linux/arm64
else ifeq ($(HOST_ARCH),aarch64)
APIM_LOCAL_PLATFORM ?= linux/arm64
else
APIM_LOCAL_PLATFORM ?= linux/amd64
endif
ifeq ($(APIM_LOCAL_PLATFORM),linux/arm64)
APIM_GOARCH := arm64
else
APIM_GOARCH := amd64
endif

DIRECT_URL := http://localhost:8000
SSO_URL := http://localhost:8307
KEYCLOAK_URL := http://localhost:8500
DEFAULT_COMPOSE_ENV := APIM_LOCAL_PLATFORM=$(APIM_LOCAL_PLATFORM)
SSO_COMPOSE_ENV := $(DEFAULT_COMPOSE_ENV) PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) APIM_CONFIG_PATH=/app/examples/sso.json

export APIM_LOCAL_PLATFORM
export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_DEMO_PASSWORD ?= local-dev-password
export OAUTH2_PROXY_COOKIE_SECRET ?= 0123456789abcdef0123456789abcdef

.PHONY: help prereqs build test update app-help app-test app-js-check app-build app-run up up-direct down urls logs ps compose-smoke compose-smoke-sso

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

app-run: ## Run the Go simulator directly on port 8000
	@$(MAKE) --no-print-directory -C app run

##@ Build and test
build: prereqs ## Build the Go binary and compose image
	@GOARCH=$(APIM_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) build apim-simulator

test: app-test app-js-check compose-smoke compose-smoke-sso ## Run Go tests, JS checks, and direct and SSO compose smoke tests

compose-smoke: ## Run the direct Go-only compose smoke test
	@./tests/compose-smoke.sh --execute

compose-smoke-sso: ## Run the local oauth2-proxy/Keycloak compose smoke test
	@./tests/compose-smoke-sso.sh --execute

update: ## No dependency locks are managed at this wrapper level
	@echo "apim-simulator: Go-only app; no package-manager locks to update"

##@ Run
up: prereqs ## Start the Keycloak + oauth2-proxy APIM stack
	@GOARCH=$(APIM_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE_CMD) --profile sso up -d --build apim-simulator keycloak oauth2-proxy
	@$(MAKE) --no-print-directory urls
	@echo "Keycloak URL:          $(KEYCLOAK_URL)"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-direct: prereqs ## Start the direct Go APIM simulator stack
	@GOARCH=$(APIM_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) up -d --build apim-simulator
	@$(MAKE) --no-print-directory urls

down: prereqs ## Stop the compose stack
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) --profile sso down --remove-orphans

urls: ## Print local URLs
	@echo "APIM Simulator URL:    $(DIRECT_URL)"
	@echo "APIM SSO URL:          $(SSO_URL)"
	@echo "Gateway health:        $(DIRECT_URL)/apim/health"

logs: prereqs ## Tail compose logs
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) logs -f --tail=200

ps: prereqs ## Show compose container status
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) ps
