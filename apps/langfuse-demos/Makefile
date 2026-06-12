MAKE_KNOWN_GOALS := help test build update app-help app-prereqs app-test app-js-check app-build app-run-chat app-run-agent app-run-evals

include ../../mk/app-common.mk

##@ App
app-prereqs: ## Check Go plus the optional host oMLX OpenAI-compatible server
	@$(MAKE) --no-print-directory -C app prereqs

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
