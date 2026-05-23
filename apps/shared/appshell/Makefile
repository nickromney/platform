.PHONY: help test js-check

help:
	@echo "Shared app shell module:"
	@echo "  test      Run Go unit tests"
	@echo "  js-check  Check vanilla JavaScript source contracts"

test:
	go test ./...

js-check:
	biome check app-shell.js
	deno check --check-js app-shell.js
