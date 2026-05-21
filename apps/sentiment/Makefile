USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build test update check-prerequisites app-test app-js-check up up-tls down logs ps smoke urls
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
PLATFORM_DEMO_PASSWORD ?= local-dev-password
OAUTH2_PROXY_COOKIE_SECRET ?= 0123456789abcdef0123456789abcdef
PLATFORM_REQUIRED_ENV_VARS :=
ifneq ($(strip $(wildcard $(PLATFORM_ENV_FILE))),)
include $(PLATFORM_ENV_FILE)
endif
SSO_COMPOSE_ENV := PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) SENTIMENT_FRONTEND_AUTH_METHOD=gateway SENTIMENT_FRONTEND_API_AUTH_METHOD=oidc SENTIMENT_BACKEND_AUTH_METHOD=oidc SENTIMENT_OIDC_ISSUER_URL=http://localhost:8300/realms/platform SENTIMENT_OIDC_JWKS_URI=http://keycloak:8080/realms/platform/protocol/openid-connect/certs SENTIMENT_OIDC_AUDIENCE=sentiment-api

APP_BASE_URL := http://localhost:8304
APP_URL := $(APP_BASE_URL)/oauth2/sign_in
APP_TLS_BASE_URL := https://localhost:8443
APP_TLS_URL := $(APP_TLS_BASE_URL)/oauth2/sign_in
KEYCLOAK_URL := http://localhost:8300
COMPOSE := $(COMPOSE_CMD) -f compose.yml
COMPOSE_TLS := $(COMPOSE_CMD) -f compose.yml -f compose.tls.yml

.PHONY: help prereqs test update check-prerequisites app-test app-js-check build up up-tls down logs ps smoke urls

export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_DEMO_PASSWORD
export OAUTH2_PROXY_COOKIE_SECRET

##@ Setup
prereqs: ## Check local prerequisites
	@$(MAKE) --no-print-directory check-prerequisites

check-prerequisites: ## Check that a supported compose backend is installed and running
	@$(MAKE) --no-print-directory check-platform-env
	@if [ -z "$(COMPOSE_CMD)" ]; then \
		echo "A supported compose backend is required but was not found." >&2; \
		exit 1; \
	fi

build: check-prerequisites ## Build the local compose images
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE) build

app-test: ## Run Go unit tests
	@$(MAKE) --no-print-directory -C app test

app-js-check: ## Check vanilla JavaScript source contracts
	@$(MAKE) --no-print-directory -C app js-check

##@ Run
up: check-prerequisites ## Start the authenticated compose stack and print the local URL
	@$(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE) up -d --build
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-tls: check-prerequisites ## Start the TLS compose stack and print the HTTPS URL
	@$(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE_TLS) up -d --build
	@echo "Sentiment URL: $(APP_TLS_URL)"
	@echo "Base URL:      $(APP_TLS_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "If the browser warns about the cert, run ./pki/gen-certs.sh and trust the local CA."

urls: ## Print the local URLs for the app and Keycloak
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Sentiment TLS: $(APP_TLS_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"

logs: check-prerequisites ## Tail compose logs
	@$(COMPOSE) logs -f --tail=200

ps: check-prerequisites ## Show compose container status
	@$(COMPOSE) ps

smoke: check-prerequisites ## Run the local compose smoke test
	@./tests/compose-smoke.sh --execute

##@ Test
test: app-test app-js-check ## Run Go tests, JS contract checks, and the local compose smoke test
	@$(MAKE) --no-print-directory smoke

update: ## Update Bun dependency locks for each sentiment dependency root
	@echo "No dependency update required for the default Go sentiment runtime."

##@ Cleanup
down: check-prerequisites ## Stop the compose stack
	@$(COMPOSE) down --remove-orphans
