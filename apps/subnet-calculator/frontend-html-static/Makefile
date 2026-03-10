.PHONY: test
test: ## Run Playwright tests
	@echo "Running Static HTML frontend tests..."
	@uv run pytest -v

.PHONY: test-docker
test-docker: ## Run tests against Docker Compose
	@uv run pytest --base-url=http://localhost:8001 -v

.PHONY: install
install: ## Install dependencies
	@uv sync --extra dev

.PHONY: serve
serve: ## Serve static files (requires Python http.server or nginx)
	@python3 -m http.server 8001

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
