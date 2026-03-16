USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help install serve test test-docker
MAKE_SUGGEST_SCRIPT := ../../../scripts/suggest-make-goal.sh

include ../../../mk/common.mk

.PHONY: help install serve test test-docker

##@ Workflow
test: ## Run Playwright tests
	@echo "Running Static HTML frontend tests..."
	@uv run pytest -v

test-docker: ## Run tests against Docker Compose
	@uv run pytest --base-url=http://localhost:8001 -v

##@ Setup
install: ## Install dependencies
	@uv sync --frozen --extra dev

##@ Run
serve: ## Serve static files (requires Python http.server or nginx)
	@python3 -m http.server 8001
