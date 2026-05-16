USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build test update check-prerequisites up up-tls up-apim-ai-gateway down logs ps smoke smoke-apim-ai-gateway urls compose-config-apim-ai-gateway
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

APP_BASE_URL := http://localhost:8304
APP_URL := $(APP_BASE_URL)/oauth2/sign_in
APP_TLS_BASE_URL := https://localhost:8443
APP_TLS_URL := $(APP_TLS_BASE_URL)/oauth2/sign_in
KEYCLOAK_URL := http://localhost:8300
COMPOSE := $(COMPOSE_CMD) -f compose.yml
COMPOSE_TLS := $(COMPOSE_CMD) -f compose.yml -f compose.tls.yml
COMPOSE_APIM_AI_GATEWAY := $(COMPOSE_CMD) -f compose.yml -f compose.apim-ai-gateway.yml

.PHONY: help prereqs test update check-prerequisites build up up-tls up-apim-ai-gateway down logs ps smoke smoke-apim-ai-gateway urls compose-config-apim-ai-gateway

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
	@$(MAKE) --no-print-directory -C app-go build-linux
	@$(COMPOSE) build

##@ Run
up: check-prerequisites ## Start the authenticated compose stack and print the local URL
	@$(MAKE) --no-print-directory -C app-go build-linux
	@$(COMPOSE) up -d --build
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-tls: check-prerequisites ## Start the TLS compose stack and print the HTTPS URL
	@$(MAKE) --no-print-directory -C app-go build-linux
	@$(COMPOSE_TLS) up -d --build
	@echo "Sentiment URL: $(APP_TLS_URL)"
	@echo "Base URL:      $(APP_TLS_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "If the browser warns about the cert, run ./pki/gen-certs.sh and trust the local CA."

up-apim-ai-gateway: check-prerequisites ## Start sentiment configured to call the APIM simulator AI gateway
	@$(MAKE) --no-print-directory -C app-go build-linux
	@$(COMPOSE_APIM_AI_GATEWAY) up -d --build
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "APIM AI URL:   $${SENTIMENT_APIM_AI_GATEWAY_URL:-http://host.docker.internal:8000/ai/v1/chat/completions}"
	@echo "Start the APIM simulator first with: make -C ../apim-simulator up-ai-gateway"

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

smoke-apim-ai-gateway: ## Smoke sentiment through the running APIM simulator AI gateway
	@./tests/compose-apim-ai-gateway-smoke.sh --execute

compose-config-apim-ai-gateway: ## Render compose config for the APIM AI gateway analyzer overlay
	@PLATFORM_DEMO_PASSWORD="$${PLATFORM_DEMO_PASSWORD:-local-dev-password}" OAUTH2_PROXY_COOKIE_SECRET="$${OAUTH2_PROXY_COOKIE_SECRET:-0123456789abcdef0123456789abcdef}" $(COMPOSE_APIM_AI_GATEWAY) config

##@ Test
test: ## Run the local compose smoke test
	@$(MAKE) --no-print-directory smoke

update: ## Update Bun dependency locks for each sentiment dependency root
	@echo "No dependency update required for the default Go sentiment runtime."
	@echo "Legacy Bun roots remain in-tree only for compatibility/reference."
	@cd frontend-typescript-vite && bun update --latest

##@ Cleanup
down: check-prerequisites ## Stop the compose stack
	@$(COMPOSE) down --remove-orphans
	@$(COMPOSE_APIM_AI_GATEWAY) down --remove-orphans
