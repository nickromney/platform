MAKE_KNOWN_GOALS := help prereqs test build update app-help app-test app-js-check app-build app-run

include ../../mk/app-common.mk

##@ App
app-run: ## Run the Auth Chat app directly
	@$(MAKE) --no-print-directory -C app run

##@ Build and test
test: app-test app-js-check ## Run Go tests and browser JavaScript checks

build: prereqs ## Build the Go binary
	@$(MAKE) --no-print-directory -C app build-linux
