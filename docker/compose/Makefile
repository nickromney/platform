USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs check-docker-prerequisites check-mkcert-prerequisites check-host-ports check-https-443-available certs config build up up-dev up-uat up-all down logs ps urls test
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk

.PHONY: help prereqs check-docker-prerequisites check-mkcert-prerequisites check-host-ports check-https-443-available certs config build up up-dev up-uat up-all down logs ps urls test

COMPOSE := docker compose -f compose.yml
COMPOSE_ENV := OAUTH2_PROXY_CLIENT_SECRET=compose-oauth2-proxy-secret OAUTH2_PROXY_COOKIE_SECRET=00000000000000000000000000000000
CHECK_HOST_PORTS := ./scripts/check-host-ports.sh

##@ Prerequisites
prereqs: ## Check that Docker Desktop and docker compose are usable
	@$(MAKE) --no-print-directory check-docker-prerequisites
	@$(MAKE) --no-print-directory check-mkcert-prerequisites

check-docker-prerequisites: ## Check that docker compose is installed and Docker is running
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
	@COMPOSE_PROJECT_NAME=compose $(CHECK_HOST_PORTS) --mode current

check-https-443-available: check-docker-prerequisites ## Check whether host port 443 is free for direct HTTPS binding
	@COMPOSE_PROJECT_NAME=compose $(CHECK_HOST_PORTS) --mode https-443

certs: check-mkcert-prerequisites ## Generate or refresh the mkcert TLS certs for the compose edge
	@./pki/gen-certs.sh

##@ Compose
config: check-docker-prerequisites ## Validate the full compose graph
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev --profile uat config -q

build: check-docker-prerequisites ## Build the shared subnetcalc compose images
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev --profile uat build apim-simulator subnetcalc-api-dev subnetcalc-api-uat subnetcalc-frontend-dev subnetcalc-frontend-uat

up: up-all ## Start the full dev + uat compose platform

up-dev: check-docker-prerequisites check-host-ports certs ## Start the shared services plus subnetcalc dev
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev up -d --build
	@$(MAKE) --no-print-directory urls

up-uat: check-docker-prerequisites check-host-ports certs ## Start the shared services plus subnetcalc uat
	@$(COMPOSE_ENV) $(COMPOSE) --profile uat up -d --build
	@$(MAKE) --no-print-directory urls

up-all: check-docker-prerequisites check-host-ports certs ## Start the shared services plus subnetcalc dev and uat
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev --profile uat up -d --build
	@$(MAKE) --no-print-directory urls

down: check-docker-prerequisites ## Stop the compose platform and remove orphaned containers
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev --profile uat down --remove-orphans

logs: check-docker-prerequisites ## Tail compose logs; optionally pass SERVICE=<name>
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev --profile uat logs -f --tail=200 $(SERVICE)

ps: check-docker-prerequisites ## Show compose container status
	@$(COMPOSE_ENV) $(COMPOSE) --profile dev --profile uat ps

urls: ## Print the operator URLs and demo credentials
	@echo "Compose edge:"
	@echo "  DEV  -> https://subnetcalc.dev.compose.127.0.0.1.sslip.io:8443"
	@echo "  UAT  -> https://subnetcalc.uat.compose.127.0.0.1.sslip.io:8443"
	@echo "  HTTP -> http://subnetcalc.dev.compose.127.0.0.1.sslip.io:8088 (redirects to HTTPS)"
	@echo ""
	@echo "Shared services:"
	@echo "  Dex debug      -> http://localhost:8300/dex/.well-known/openid-configuration"
	@echo "  Dex public     -> https://dex.compose.127.0.0.1.sslip.io:8443/dex"
	@echo "  APIM health    -> http://localhost:8302/apim/health"
	@echo ""
	@echo "Demo credentials:"
	@echo "  DEV user   -> demo@dev.test / demo-password"
	@echo "  UAT user   -> demo@uat.test / demo-password"
	@echo "  Admin user -> demo@admin.test / demo-password"
	@echo ""
	@echo "Note:"
	@echo "  Compose defaults to :8443 so it can coexist with kind on 127.0.0.1:443."
	@echo "  Run 'make -C docker/compose check-https-443-available' before attempting direct :443."

##@ Verification
test: config ## Validate the compose topology renders cleanly
