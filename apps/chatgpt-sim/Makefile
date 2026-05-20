.PHONY: help test build update app-help app-test app-build app-run-mcp app-run-shell up down logs ps compose-smoke

COMPOSE_CMD ?= docker compose -f compose.yml

help:
	@echo "ChatGPT Sim:"
	@echo "  app-test       Run Go unit tests"
	@echo "  app-build      Build the local app binary"
	@echo "  app-run-mcp    Run the MCP role directly"
	@echo "  app-run-shell  Run the shell role directly"
	@echo "  compose-smoke  Run the app-local compose smoke test"
	@echo "  up             Start the app-local compose stack"
	@echo "  down           Stop the app-local compose stack"

app-help:
	@$(MAKE) --no-print-directory -C app help

app-test:
	@$(MAKE) --no-print-directory -C app test

app-build:
	@$(MAKE) --no-print-directory -C app build

app-run-mcp:
	@$(MAKE) --no-print-directory -C app run-mcp

app-run-shell:
	@$(MAKE) --no-print-directory -C app run-shell

test: app-test compose-smoke

build:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) build

update:
	@echo "chatgpt-sim has no dependency lock update workflow"

compose-smoke:
	@./tests/compose-smoke.sh --execute

up:
	@$(MAKE) --no-print-directory -C app build-linux
	@$(COMPOSE_CMD) up -d --build
	@echo "ChatGPT Sim URL: http://localhost:18084"

down:
	@$(COMPOSE_CMD) down --remove-orphans

logs:
	@$(COMPOSE_CMD) logs -f

ps:
	@$(COMPOSE_CMD) ps
