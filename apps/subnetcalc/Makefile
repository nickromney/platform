MAKE_KNOWN_GOALS := help prereqs build test update app-help app-test app-js-check app-build app-run-backend app-run-frontend up up-direct down urls logs ps compose-smoke compose-smoke-sso

include ../../mk/app-common.mk

SUBNETCALC_LOCAL_PLATFORM ?= $(APP_LOCAL_PLATFORM)
ifeq ($(SUBNETCALC_LOCAL_PLATFORM),linux/arm64)
SUBNETCALC_GOARCH := arm64
else
SUBNETCALC_GOARCH := amd64
endif
export SUBNETCALC_LOCAL_PLATFORM

DEFAULT_STACK_URL := http://localhost:8003
DEFAULT_API_HEALTH_URL := http://localhost:8090/api/v1/health
DEFAULT_COMPOSE_ENV := SUBNETCALC_LOCAL_PLATFORM=$(SUBNETCALC_LOCAL_PLATFORM)
APP_COMPOSE_ENV := $(DEFAULT_COMPOSE_ENV)
SSO_COMPOSE_ENV := $(DEFAULT_COMPOSE_ENV) PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) SUBNETCALC_PUBLIC_PORT=8003 SUBNETCALC_FRONTEND_PORT=18003 SUBNETCALC_BACKEND_PORT=18090 SUBNETCALC_KEYCLOAK_PORT=8400 SUBNETCALC_FRONTEND_AUTH_METHOD=gateway SUBNETCALC_BACKEND_AUTH_METHOD=oidc SUBNETCALC_OIDC_ISSUER_URL=http://localhost:8400/realms/platform SUBNETCALC_OIDC_JWKS_URI=http://keycloak:8080/realms/platform/protocol/openid-connect/certs SUBNETCALC_OIDC_AUDIENCE=api-app

##@ App
app-run-backend: ## Run the backend role directly on port 8090
	@$(MAKE) --no-print-directory -C app run-backend

app-run-frontend: ## Run the frontend role directly on port 8003
	@$(MAKE) --no-print-directory -C app run-frontend

##@ Build and test
build: prereqs ## Build the Go binary and compose image
	@GOARCH=$(SUBNETCALC_GOARCH) $(MAKE) --no-print-directory -C app build-linux
	@$(DEFAULT_COMPOSE_ENV) $(COMPOSE_CMD) build subnetcalc-backend subnetcalc-frontend

test: app-test app-js-check compose-smoke compose-smoke-sso ## Run Go tests, JS contract checks, and direct and SSO compose smoke tests

compose-smoke-sso: ## Run the SSO compose smoke test
	@./tests/compose-smoke-sso.sh --execute

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

urls: ## Print local URLs
	@echo "Subnet Calculator URL: $(DEFAULT_STACK_URL)"
	@echo "API health:            $(DEFAULT_API_HEALTH_URL)"
