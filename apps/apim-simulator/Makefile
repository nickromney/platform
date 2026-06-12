MAKE_KNOWN_GOALS := help prereqs build test update app-help app-test app-js-check app-build app-run up up-direct down urls logs ps compose-smoke compose-smoke-sso

include ../../mk/app-common.mk

APIM_LOCAL_PLATFORM ?= $(APP_LOCAL_PLATFORM)
ifeq ($(APIM_LOCAL_PLATFORM),linux/arm64)
APIM_GOARCH := arm64
else
APIM_GOARCH := amd64
endif
export APIM_LOCAL_PLATFORM

DIRECT_URL := http://localhost:8000
SSO_URL := http://localhost:8307
KEYCLOAK_URL := http://localhost:8500
DEFAULT_COMPOSE_ENV := APIM_LOCAL_PLATFORM=$(APIM_LOCAL_PLATFORM)
APP_COMPOSE_ENV := $(DEFAULT_COMPOSE_ENV)
APP_COMPOSE_DOWN_ARGS := --profile sso
SSO_COMPOSE_ENV := $(DEFAULT_COMPOSE_ENV) PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) APIM_CONFIG_PATH=/app/examples/sso.json

##@ App
app-run: ## Run the Go simulator directly on port 8000
	@$(MAKE) --no-print-directory -C app run

##@ Build and test
build: prereqs ## Build the Go binary and compose image
	@GOARCH=$(APIM_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) build apim-simulator

test: app-test app-js-check compose-smoke compose-smoke-sso ## Run Go tests, JS checks, and direct and SSO compose smoke tests

compose-smoke-sso: ## Run the local oauth2-proxy/Keycloak compose smoke test
	@./tests/compose-smoke-sso.sh --execute

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

urls: ## Print local URLs
	@echo "APIM Simulator URL:    $(DIRECT_URL)"
	@echo "APIM SSO URL:          $(SSO_URL)"
	@echo "Gateway health:        $(DIRECT_URL)/apim/health"
