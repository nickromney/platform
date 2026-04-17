USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs install update dev test test-headless
MAKE_SUGGEST_SCRIPT := ../../../scripts/suggest-make-goal.sh

include ../../../mk/common.mk

.PHONY: help prereqs install update dev test test-headless

##@ Workflow
test: ## Run Playwright tests
	@echo "Running Flask frontend tests..."
	@uv run pytest -v

test-headless: ## Run tests in headless mode
	@uv run pytest -v --headed=false

##@ Setup
prereqs: ## Install local frontend prerequisites
	@$(MAKE) --no-print-directory install

install: ## Install dependencies
	@uv sync --frozen --extra dev

update: ## Update uv lockfile and sync dev dependencies
	@uv lock --upgrade
	@uv sync --group dev

##@ Run
dev: ## Run development server
	@uv run flask run
