USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help test build update app-help app-prereqs app-test app-js-check app-build app-run-chat app-run-agent app-run-evals
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk

.PHONY: help test build update app-help app-prereqs app-test app-js-check app-build app-run-chat app-run-agent app-run-evals

##@ App
app-help: ## Show app Makefile targets
	@$(MAKE) --no-print-directory -C app help

app-prereqs: ## Check Go plus the optional host oMLX OpenAI-compatible server
	@$(MAKE) --no-print-directory -C app prereqs

app-test: ## Run Go unit tests
	@$(MAKE) --no-print-directory -C app test

app-js-check: ## Check vanilla JavaScript source contracts
	@$(MAKE) --no-print-directory -C app js-check

app-build: ## Build the local app binary
	@$(MAKE) --no-print-directory -C app build

app-run-chat: ## Run the trace chat role
	@$(MAKE) --no-print-directory -C app run-chat

app-run-agent: ## Run the tool agent role
	@$(MAKE) --no-print-directory -C app run-agent

app-run-evals: ## Run the eval runner role
	@$(MAKE) --no-print-directory -C app run-evals

##@ Build and test
test: app-test app-js-check ## Run Go tests and JS contract checks

build: ## Build the Go binary
	@$(MAKE) --no-print-directory -C app build-linux

update: ## No dependency locks are managed at this wrapper level
	@echo "langfuse-demos: Go-only app; no package-manager locks to update"
