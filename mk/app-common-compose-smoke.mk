##@ Build and test
.PHONY: compose-smoke
compose-smoke: ## Run the app-local compose smoke test
	@./tests/compose-smoke.sh --execute
