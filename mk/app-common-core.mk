# App-core delegation targets shared by apps/<name>/Makefile wrappers.
# Included conditionally from mk/app-common.mk; each public rule is only
# defined when the wrapper declares it in MAKE_KNOWN_GOALS.

##@ App
ifneq ($(filter app-help,$(MAKE_KNOWN_GOALS)),)
.PHONY: app-help
app-help: ## Show app Makefile targets
	@$(MAKE) --no-print-directory -C app help
endif

ifneq ($(filter app-test,$(MAKE_KNOWN_GOALS)),)
.PHONY: app-test
app-test: ## Run Go unit tests
	@$(MAKE) --no-print-directory -C app test
endif

ifneq ($(filter app-js-check,$(MAKE_KNOWN_GOALS)),)
.PHONY: app-js-check
app-js-check: ## Check vanilla JavaScript source contracts
	@$(MAKE) --no-print-directory -C app js-check
endif

ifneq ($(filter app-build,$(MAKE_KNOWN_GOALS)),)
.PHONY: app-build
app-build: ## Build the local app binary
	@$(MAKE) --no-print-directory -C app build
endif
