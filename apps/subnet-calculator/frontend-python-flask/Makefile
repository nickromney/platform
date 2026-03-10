.PHONY: test
test: ## Run Playwright tests
	@echo "Running Flask frontend tests..."
	@uv run pytest -v

.PHONY: test-headless
test-headless: ## Run tests in headless mode
	@uv run pytest -v --headed=false

.PHONY: install
install: ## Install dependencies
	@uv sync --extra dev

.PHONY: dev
dev: ## Run development server
	@uv run flask run

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
