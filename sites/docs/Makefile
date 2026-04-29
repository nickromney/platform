SHELL := /bin/bash
USE_COMMON_HELP := 1
MAKE_HELP_WIDTH := 20

.DEFAULT_GOAL := help

include ../../mk/common.mk

NODE_MODULES_STAMP := node_modules/.bun-install.stamp

.PHONY: prereqs check-bun install dev build local test lint typecheck check-d2 clean

prereqs: check-bun $(NODE_MODULES_STAMP) ## Verify docs-site prerequisites and install dependencies
	@echo "Docs-site prerequisites satisfied"

check-bun:
	@command -v bun >/dev/null 2>&1 || { echo "bun is required but was not found in PATH." >&2; exit 1; }

install: ## Install the docs-site dependencies with Bun
	bun install
	@touch "$(NODE_MODULES_STAMP)"

$(NODE_MODULES_STAMP): package.json bun.lock
	bun install
	@touch "$@"

dev: $(NODE_MODULES_STAMP) ## Start the local Nextra development server
	bun run dev

build: $(NODE_MODULES_STAMP) ## Build the Nextra docs site
	bun run build

local: $(NODE_MODULES_STAMP) ## Build and serve the production docs site locally
	bun run local

test: $(NODE_MODULES_STAMP) ## Run docs content and diagram integrity checks
	bun run test:docs

lint: $(NODE_MODULES_STAMP) ## Run docs content lint
	bun run lint:content

typecheck: $(NODE_MODULES_STAMP) ## Run TypeScript without emitting files
	bun run typecheck

check-d2: $(NODE_MODULES_STAMP) ## Verify rendered D2 diagrams match their sources
	bun run check:d2

clean: ## Remove local docs-site build and dependency output
	rm -rf .next node_modules tsconfig.tsbuildinfo
