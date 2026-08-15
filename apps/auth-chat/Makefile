MAKE_KNOWN_GOALS := help test build update app-help app-prereqs app-test app-js-check app-build app-run

include ../../mk/app-common.mk

##@ App
app-prereqs: ## Check the Go toolchain needed to build and run the app
	@$(MAKE) --no-print-directory -C app prereqs

app-run: ## Run the Auth Chat app directly
	@$(MAKE) --no-print-directory -C app run

##@ Build and test
test: app-test app-js-check ## Run Go tests and browser JavaScript checks

build: ## Build the Go binary
	@$(MAKE) --no-print-directory -C app build-linux
