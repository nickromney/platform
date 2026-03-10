.PHONY: test
test: ## Run Playwright tests
	@echo "Running TypeScript frontend tests..."
	@npm test

.PHONY: test-headed
test-headed: ## Run tests with browser visible
	@npm run test:headed

.PHONY: test-ui
test-ui: ## Run tests with Playwright UI
	@npm run test:ui

.PHONY: install
install: ## Install dependencies
	@npm install

.PHONY: dev
dev: ## Run development server
	@npm run dev

.PHONY: build
build: ## Build for production
	@npm run build

.PHONY: lint
lint: ## Run linting
	@npm run lint

.PHONY: type-check
type-check: ## Run TypeScript type checking
	@npm run type-check

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'
