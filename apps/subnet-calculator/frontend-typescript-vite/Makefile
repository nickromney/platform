USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs install update dev build lint type-check test test-headed test-ui
MAKE_SUGGEST_SCRIPT := ../../../scripts/suggest-make-goal.sh

include ../../../mk/common.mk

.PHONY: help prereqs install update dev build lint type-check test test-headed test-ui

##@ Workflow
test: ## Run Playwright tests
	@echo "Running TypeScript frontend tests..."
	@bun run test

test-headed: ## Run tests with browser visible
	@bun run test:headed

test-ui: ## Run tests with Playwright UI
	@bun run test:ui

##@ Setup
prereqs: ## Install local frontend prerequisites
	@$(MAKE) --no-print-directory install

install: ## Install dependencies
	@bun install --frozen-lockfile

update: ## Update Bun dependency locks
	@bun update --latest

##@ Run
dev: ## Run development server
	@bun run dev

build: ## Build for production
	@bun run build

##@ Quality
lint: ## Run linting
	@bun run lint

type-check: ## Run TypeScript type checking
	@bun run type-check
