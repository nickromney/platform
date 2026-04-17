USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build test update check-prerequisites up up-tls down logs ps smoke urls
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk
include ../../mk/compose.mk

APP_BASE_URL := http://localhost:8304
APP_URL := $(APP_BASE_URL)/oauth2/sign_in
APP_TLS_BASE_URL := https://localhost:8443
APP_TLS_URL := $(APP_TLS_BASE_URL)/oauth2/sign_in
KEYCLOAK_URL := http://localhost:8300
COMPOSE := $(COMPOSE_CMD) -f compose.yml
COMPOSE_TLS := $(COMPOSE_CMD) -f compose.yml -f compose.tls.yml

.PHONY: help prereqs test update check-prerequisites build up up-tls down logs ps smoke urls

##@ Setup
prereqs: ## Check local prerequisites
	@$(MAKE) --no-print-directory check-prerequisites

check-prerequisites: ## Check that a supported compose backend is installed and running
	@if [ -z "$(COMPOSE_CMD)" ]; then \
		echo "A supported compose backend is required but was not found." >&2; \
		exit 1; \
	fi

build: check-prerequisites ## Build the local compose images
	@$(COMPOSE) build

##@ Run
up: check-prerequisites ## Start the authenticated compose stack and print the local URL
	@$(COMPOSE) up -d --build
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-tls: check-prerequisites ## Start the TLS compose stack and print the HTTPS URL
	@$(COMPOSE_TLS) up -d --build
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
test: ## Run the local compose smoke test
	@$(MAKE) --no-print-directory smoke

update: ## Update Bun dependency locks for each sentiment dependency root
	@cd api-sentiment && bun update --latest
	@cd frontend-react-vite/sentiment-auth-ui && bun update --latest
	@cd frontend-typescript-vite && bun update --latest

##@ Cleanup
down: check-prerequisites ## Stop the compose stack
	@$(COMPOSE) down --remove-orphans
