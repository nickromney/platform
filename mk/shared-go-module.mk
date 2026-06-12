.PHONY: help test

SHARED_GO_MODULE_JS_CHECK_SOURCES ?=

ifeq ($(strip $(SHARED_GO_MODULE_JS_CHECK_SOURCES)),)
help:
	@echo "$(SHARED_GO_MODULE_LABEL):"
	@echo "  test  Run Go unit tests"
else
.PHONY: js-check

help:
	@echo "$(SHARED_GO_MODULE_LABEL):"
	@echo "  test      Run Go unit tests"
	@echo "  js-check  Check vanilla JavaScript source contracts"
endif

test:
	go test ./...

ifneq ($(strip $(SHARED_GO_MODULE_JS_CHECK_SOURCES)),)
js-check:
	biome check $(SHARED_GO_MODULE_JS_CHECK_SOURCES)
	deno check --check-js $(SHARED_GO_MODULE_JS_CHECK_SOURCES)
endif
