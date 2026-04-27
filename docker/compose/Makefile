USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs check-docker-prerequisites check-mkcert-prerequisites check-host-ports check-https-443-available certs config build up up-dev up-uat up-portal up-all down logs ps urls check-backstage test test-backstage
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
OAUTH2_PROXY_COOKIE_SECRET ?=
PLATFORM_REQUIRED_ENV_VARS := OAUTH2_PROXY_COOKIE_SECRET
ifneq ($(strip $(wildcard $(PLATFORM_ENV_FILE))),)
include $(PLATFORM_ENV_FILE)
endif

.PHONY: help prereqs check-docker-prerequisites check-mkcert-prerequisites check-host-ports check-https-443-available certs config build up up-dev up-uat up-portal up-all down logs ps urls check-backstage test test-backstage

COMPOSE := $(COMPOSE_CMD) -f compose.yml
COMPOSE_ENV := OAUTH2_PROXY_CLIENT_SECRET=compose-oauth2-proxy-secret
COMPOSE_TEST_COOKIE_SECRET := 0123456789abcdef0123456789abcdef
COMPOSE_TEST_ENV := $(COMPOSE_ENV) OAUTH2_PROXY_COOKIE_SECRET=$${OAUTH2_PROXY_COOKIE_SECRET:-$(COMPOSE_TEST_COOKIE_SECRET)}
CHECK_HOST_PORTS := ./scripts/check-host-ports.sh
CHECK_BACKSTAGE := ./scripts/check-backstage.sh
COMPOSE_BACKSTAGE_E2E_DIR := ../../tests/kubernetes/sso

export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export OAUTH2_PROXY_COOKIE_SECRET

##@ Prerequisites
prereqs: ## Check that a supported compose backend and mkcert are usable
	@$(MAKE) --no-print-directory check-platform-env
	@$(MAKE) --no-print-directory check-docker-prerequisites
	@$(MAKE) --no-print-directory check-mkcert-prerequisites

check-docker-prerequisites: ## Check that a supported compose backend is installed and running
	@if [ -z "$(COMPOSE_CMD)" ]; then \
		echo "A supported compose backend is required but was not found." >&2; \
		exit 1; \
	fi

check-mkcert-prerequisites: ## Check that mkcert is installed and its local CA exists
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

check-host-ports: check-docker-prerequisites ## Check that the compose host ports are free before startup
	@COMPOSE_PROJECT_NAME=compose $(CHECK_HOST_PORTS) --execute --mode current

check-https-443-available: check-docker-prerequisites ## Check whether host port 443 is free for direct HTTPS binding
	@COMPOSE_PROJECT_NAME=compose $(CHECK_HOST_PORTS) --execute --mode https-443

certs: check-mkcert-prerequisites ## Generate or refresh the mkcert TLS certs for the compose edge
	@./pki/gen-certs.sh --execute

##@ Compose
config: check-docker-prerequisites ## Validate the full compose graph
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal config -q

build: check-docker-prerequisites ## Build the shared compose app images
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal build apim-simulator subnetcalc-api-dev subnetcalc-api-uat subnetcalc-frontend-dev subnetcalc-frontend-uat backstage

up: up-all ## Start the full dev + uat compose platform

up-dev: check-docker-prerequisites check-host-ports certs ## Start the shared services plus subnetcalc dev
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev up -d --build
	@$(MAKE) --no-print-directory urls

up-uat: check-docker-prerequisites check-host-ports certs ## Start the shared services plus subnetcalc uat
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile uat up -d --build
	@$(MAKE) --no-print-directory urls

up-portal: check-docker-prerequisites check-host-ports certs ## Start the shared services plus Backstage portal
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile portal up -d --build edge dex backstage oauth2-proxy-backstage
	@$(MAKE) --no-print-directory urls

up-all: check-docker-prerequisites check-host-ports certs ## Start the shared services plus subnetcalc dev and uat
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal up -d --build
	@$(MAKE) --no-print-directory urls

down: check-docker-prerequisites ## Stop the compose platform and remove orphaned containers
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal down --remove-orphans

logs: check-docker-prerequisites ## Tail compose logs; optionally pass SERVICE=<name>
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal logs -f --tail=200 $(SERVICE)

ps: check-docker-prerequisites ## Show compose container status
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal ps

urls: ## Print the operator URLs and demo credentials
	@echo "Compose edge:"
	@echo "  DEV  -> https://subnetcalc.dev.compose.127.0.0.1.sslip.io:8443"
	@echo "  UAT  -> https://subnetcalc.uat.compose.127.0.0.1.sslip.io:8443"
	@echo "  Portal -> https://portal.compose.127.0.0.1.sslip.io:8443"
	@echo "  HTTP -> http://subnetcalc.dev.compose.127.0.0.1.sslip.io:8088 (redirects to HTTPS)"
	@echo ""
	@echo "Shared services:"
	@echo "  Dex debug      -> http://localhost:8300/dex/.well-known/openid-configuration"
	@echo "  Dex public     -> https://dex.compose.127.0.0.1.sslip.io:8443/dex"
	@echo "  APIM health    -> http://localhost:8302/apim/health"
	@echo ""
	@echo "Demo credentials:"
	@echo "  DEV user   -> demo@dev.test / password123"
	@echo "  UAT user   -> demo@uat.test / password123"
	@echo "  Admin user -> demo@admin.test / password123"
	@echo ""
	@echo "Note:"
	@echo "  Compose defaults to :8443 so it can coexist with kind on 127.0.0.1:443."
	@echo "  Run 'make -C docker/compose check-https-443-available' before attempting direct :443."

##@ Verification
check-backstage: check-docker-prerequisites check-host-ports certs ## Start and smoke-check the Backstage compose portal
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile portal up -d --build edge dex backstage oauth2-proxy-backstage
	@OAUTH2_PROXY_CLIENT_SECRET=compose-oauth2-proxy-secret OAUTH2_PROXY_COOKIE_SECRET=$${OAUTH2_PROXY_COOKIE_SECRET:-$(COMPOSE_TEST_COOKIE_SECRET)} COMPOSE_COMMAND="$(COMPOSE) --profile portal" $(CHECK_BACKSTAGE) --execute

test: check-docker-prerequisites ## Validate the compose topology renders cleanly
	@bats ../../tests/backstage-compose.bats
	@$(COMPOSE_TEST_ENV) $(COMPOSE) --profile dev --profile uat --profile portal config -q

test-backstage: check-backstage ## Run the live Backstage compose red/green smoke proof
	@cd $(COMPOSE_BACKSTAGE_E2E_DIR) && bun install --frozen-lockfile
	@cd $(COMPOSE_BACKSTAGE_E2E_DIR) && bun x playwright install chromium
	@cd $(COMPOSE_BACKSTAGE_E2E_DIR) && \
		COMPOSE_BACKSTAGE_URL=https://portal.compose.127.0.0.1.sslip.io:8443/ \
		COMPOSE_DEX_URL=https://dex.compose.127.0.0.1.sslip.io:8443/dex/ \
		COMPOSE_DEX_LOGIN=$${COMPOSE_DEX_LOGIN:-demo@dev.test} \
		COMPOSE_DEX_PASSWORD=$${COMPOSE_DEX_PASSWORD:-$${PLATFORM_DEMO_PASSWORD:-password123}} \
		COMPOSE_BACKSTAGE_E2E=1 \
		bun x playwright test tests/compose-backstage-smoke.spec.ts --config playwright.config.ts
