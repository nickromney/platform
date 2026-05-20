.PHONY: help test build update app-help app-test app-build app-run up down logs ps compose-smoke

COMPOSE_CMD ?= docker compose -f compose.yml

help:
	@echo "Platform MCP:"
	@echo "  app-test       Run Go unit tests"
	@echo "  app-build      Build the local app binary"
	@echo "  app-run        Run the MCP server directly"
	@echo "  compose-smoke  Run the app-local compose smoke test"
	@echo "  up             Start the app-local compose stack"
	@echo "  down           Stop the app-local compose stack"

app-help:
	@$(MAKE) --no-print-directory -C app help

app-test:
	@$(MAKE) --no-print-directory -C app test

app-build:
	@$(MAKE) --no-print-directory -C app build

app-run:
	@$(MAKE) --no-print-directory -C app run

test: app-test compose-smoke

build:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

update:
	@echo "platform-mcp has no dependency lock update workflow"

compose-smoke:
	@./tests/compose-smoke.sh --execute

up:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "Platform MCP URL: http://localhost:18085/mcp"

down:
	@$(COMPOSE_CMD) down --remove-orphans

logs:
	@$(COMPOSE_CMD) logs -f

ps:
	@$(COMPOSE_CMD) ps
