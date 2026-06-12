MAKE_KNOWN_GOALS := help prereqs test build update app-help app-test app-build app-run up down logs ps compose-smoke

include ../../mk/app-common.mk

##@ App
app-run: ## Run the MCP server directly
	@$(MAKE) --no-print-directory -C app run

##@ Build and test
test: app-test compose-smoke ## Run Go tests and the app-local compose smoke test

build: prereqs ## Build the Go binary and compose image
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

##@ Run
up: prereqs ## Start the app-local compose stack
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "Platform MCP URL: http://localhost:18085/mcp"
