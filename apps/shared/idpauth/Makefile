.PHONY: help test js-check

help:
	@echo "Shared IDP auth module:"
	@echo "  test      Run Go unit tests"
	@echo "  js-check  Check vanilla JavaScript source contracts"

test:
	go test ./...

js-check:
	biome check web/idpauth.js
	deno check --check-js web/idpauth.js
