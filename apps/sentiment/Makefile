MAKE_KNOWN_GOALS := help prereqs build test update check-prerequisites app-test app-js-check up up-tls down logs ps smoke compose-smoke urls

include ../../mk/app-common.mk

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
COMPOSE = $(COMPOSE_CMD) -f compose.yml
COMPOSE_TLS = $(COMPOSE_CMD) -f compose.yml -f compose.tls.yml

##@ Setup
check-prerequisites: prereqs ## Compatibility alias for prereqs

build: prereqs ## Build the local compose images
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE) build

##@ Run
up: prereqs ## Start the authenticated compose stack and print the local URL
	@$(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE) up -d --build
	@echo "Sentiment URL: $(APP_URL)"
	@echo "Base URL:      $(APP_BASE_URL)"
	@echo "Keycloak URL:  $(KEYCLOAK_URL)"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-tls: prereqs ## Start the TLS compose stack and print the HTTPS URL
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

smoke: compose-smoke ## Alias for compose-smoke

##@ Test
test: app-test app-js-check ## Run Go tests, JS contract checks, and the local compose smoke test
	@$(MAKE) --no-print-directory compose-smoke
