USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs install update serve test test-docker
MAKE_SUGGEST_SCRIPT := ../../../scripts/suggest-make-goal.sh

include ../../../mk/common.mk

.PHONY: help prereqs install update serve test test-docker

##@ Workflow
test: ## Run Playwright tests
	@echo "Running Static HTML frontend tests..."
	@uv run pytest -v

test-docker: ## Run tests against Docker Compose
	@uv run pytest --base-url=http://localhost:8001 -v

##@ Setup
prereqs: ## Install local frontend prerequisites
	@$(MAKE) --no-print-directory install

install: ## Install dependencies
	@uv sync --frozen --extra dev

update: ## Update uv lockfile and sync dev dependencies
	@uv lock --upgrade
	@uv sync --group dev

##@ Run
serve: ## Serve static files (requires Python http.server or nginx)
	@uv run --isolated python -m http.server 8001
