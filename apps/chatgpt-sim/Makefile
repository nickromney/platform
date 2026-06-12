MAKE_KNOWN_GOALS := help prereqs test build update app-help app-test app-js-check app-build app-run-mcp app-run-shell up up-direct down logs ps compose-smoke compose-smoke-sso

include ../../mk/app-common.mk

SSO_COMPOSE_ENV := PLATFORM_DEMO_PASSWORD=$(PLATFORM_DEMO_PASSWORD) OAUTH2_PROXY_COOKIE_SECRET=$(OAUTH2_PROXY_COOKIE_SECRET) CHATGPT_SIM_PUBLIC_PORT=18084 CHATGPT_SIM_APP_PORT=18085 CHATGPT_SIM_KEYCLOAK_PORT=8500

##@ App
app-run-mcp: ## Run the MCP role directly
	@$(MAKE) --no-print-directory -C app run-mcp

app-run-shell: ## Run the shell role directly
	@$(MAKE) --no-print-directory -C app run-shell

##@ Build and test
test: app-test app-js-check compose-smoke compose-smoke-sso ## Run Go tests, JS checks, and direct and SSO compose smoke tests

compose-smoke-sso: ## Run the app-local SSO compose smoke test
	@./tests/compose-smoke-sso.sh --execute

build: prereqs ## Build the Go binary and compose image
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

##@ Run
up: prereqs ## Start the app-local SSO compose stack
	@$(MAKE) --no-print-directory -C app build-linux
	@$(SSO_COMPOSE_ENV) $(COMPOSE_CMD) --profile sso up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"
	@echo "Keycloak URL:    http://localhost:8500"
	@echo "Keycloak can take a couple of minutes to become ready on cold start."

up-direct: prereqs ## Start the direct app-local compose stack
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"
