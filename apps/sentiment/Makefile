USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help check-prerequisites up up-tls down logs ps smoke urls
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk

APP_BASE_URL := http://localhost:8304
APP_URL := $(APP_BASE_URL)/oauth2/sign_in
APP_TLS_BASE_URL := https://localhost:8443
APP_TLS_URL := $(APP_TLS_BASE_URL)/oauth2/sign_in
KEYCLOAK_URL := http://localhost:8300

.PHONY: help check-prerequisites up up-tls down logs ps smoke urls

##@ Setup
check-prerequisites: ## Check that docker compose is installed and Docker is running
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "docker is required but was not found in PATH." >&2; \
		exit 1; \
	fi
	@if ! docker compose version >/dev/null 2>&1; then \
		echo "'docker compose' is required but not available." >&2; \
		exit 1; \
	fi
	@if ! docker info >/dev/null 2>&1; then \
		echo "Docker is not running. Start Docker Desktop and try again." >&2; \
		exit 1; \
	fi

##@ Run
up: check-prerequisites ## Start the authenticated compose stack and print the local URL
	@docker compose up -d --build
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-tls: check-prerequisites ## Start the TLS compose stack and print the HTTPS URL
	@docker compose -f compose.yml -f compose.tls.yml up -d --build
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
	@docker compose logs -f --tail=200

ps: check-prerequisites ## Show compose container status
	@docker compose ps

smoke: check-prerequisites ## Run the local compose smoke test
	@./tests/compose-smoke.sh

##@ Cleanup
down: check-prerequisites ## Stop the compose stack
	@docker compose down --remove-orphans
