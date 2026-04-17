USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs install update dev build preview test lint format type-check docker-build docker-run clean
MAKE_SUGGEST_SCRIPT := ../../../scripts/suggest-make-goal.sh

include ../../../mk/common.mk

.PHONY: help prereqs install update dev build preview test lint format type-check docker-build docker-run clean

##@ Setup
prereqs: ## Install local frontend prerequisites
	@$(MAKE) --no-print-directory install

install: ## Install dependencies
	@bun install --frozen-lockfile

update: ## Update Bun dependency locks
	@deps="$$(jq -r '((.dependencies // {}) + (.devDependencies // {}) + (.optionalDependencies // {})) | to_entries[] | select((.value | startswith("file:")) | not) | .key' package.json | tr '\n' ' ')"; \
	before_package="$$(mktemp)"; \
	before_lock="$$(mktemp)"; \
	output="$$(mktemp)"; \
	cp package.json "$$before_package"; \
	cp bun.lock "$$before_lock"; \
	if [ -n "$$deps" ]; then \
		if ! bun update --latest $$deps >"$$output" 2>&1; then \
			cat "$$output"; \
			rm -f "$$before_package" "$$before_lock" "$$output"; \
			exit 1; \
		fi; \
		if cmp -s package.json "$$before_package" && cmp -s bun.lock "$$before_lock"; then \
			echo "Bun dependencies already current."; \
		else \
			cat "$$output"; \
		fi; \
	else \
		echo "No registry-backed Bun dependencies to update."; \
	fi; \
	rm -f "$$before_package" "$$before_lock" "$$output"

##@ Run
dev: ## Start the development server
	@bun run dev

build: ## Build for production
	@bun run build

preview: ## Preview the production build
	@bun run preview

##@ Quality
test: ## Run Playwright tests
	@bun run test

lint: ## Run Biome linting
	@bun run lint

format: ## Format code with Biome
	@bun run format

type-check: ## Run TypeScript type checking
	@bun run type-check

##@ Container
docker-build: ## Build the Docker image
	@docker build -t subnet-calculator-react .

docker-run: ## Run the Docker container
	@docker run -p 8080:8080 subnet-calculator-react

##@ Cleanup
clean: ## Remove generated artifacts
	@rm -rf node_modules dist .vite coverage playwright-report test-results
