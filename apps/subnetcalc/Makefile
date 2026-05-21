USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build test update app-help app-test app-js-check app-build app-run-backend app-run-frontend up up-direct down urls logs ps compose-smoke compose-smoke-sso
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
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
SSO_COMPOSE_ENV := $(DEFAULT_COMPOSE_ENV) PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) SUBNETCALC_PUBLIC_PORT=8003 SUBNETCALC_FRONTEND_PORT=18003 SUBNETCALC_BACKEND_PORT=18090 SUBNETCALC_KEYCLOAK_PORT=8400 SUBNETCALC_FRONTEND_AUTH_METHOD=gateway SUBNETCALC_BACKEND_AUTH_METHOD=oidc SUBNETCALC_OIDC_ISSUER_URL=http://localhost:8400/realms/platform SUBNETCALC_OIDC_JWKS_URI=http://keycloak:8080/realms/platform/protocol/openid-connect/certs SUBNETCALC_OIDC_AUDIENCE=api-app

export SUBNETCALC_LOCAL_PLATFORM
export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_DEMO_PASSWORD ?= local-dev-password
export OAUTH2_PROXY_COOKIE_SECRET ?= 0123456789abcdef0123456789abcdef

.PHONY: help prereqs build test update app-help app-test app-js-check app-build app-run-backend app-run-frontend up up-direct down urls logs ps compose-smoke compose-smoke-sso

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

test: app-test app-js-check compose-smoke compose-smoke-sso ## Run Go tests, JS contract checks, and direct and SSO compose smoke tests

compose-smoke: ## Run the Go-only compose smoke test
	@./tests/compose-smoke.sh --execute

compose-smoke-sso: ## Run the SSO compose smoke test
	@./tests/compose-smoke-sso.sh --execute

update: ## No dependency locks are managed at this wrapper level
	@echo "subnetcalc: Go-only app; no package-manager locks to update"

##@ Run
up: prereqs ## Start the Keycloak + oauth2-proxy compose stack
	@GOARCH=$(SUBNETCALC_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE_CMD) --profile sso up -d --build subnetcalc-backend subnetcalc-frontend edge keycloak oauth2-proxy
	@$(MAKE) --no-print-directory urls
	@echo "Keycloak URL:          http://localhost:8400"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-direct: prereqs ## Start the direct Go frontend and backend compose stack
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
