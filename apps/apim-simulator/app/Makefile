.PHONY: help test js-check build build-linux run

APIM_SIMULATOR_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

help:
	@echo "App:"
	@echo "  test         Run Go unit tests"
	@echo "  js-check     Check vanilla JavaScript source contracts"
	@echo "  build        Build the local binary at .run/apim-simulator"
	@echo "  build-linux  Build the Linux binary used by compose"
	@echo "  run          Run the simulator locally on port 8000"

test:
	go test ./...

js-check:
	biome check internal/app/web/app.js internal/app/web/index.html internal/app/web/styles.css
	deno check --check-js internal/app/web/app.js

build:
	go build -trimpath -ldflags="-s -w" -o .run/apim-simulator ./cmd/apim-simulator

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(APIM_SIMULATOR_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/apim-simulator ./cmd/apim-simulator

run:
	PORT=8000 APIM_CONFIG_PATH=../examples/basic.json APIM_CONFIG_TEMPLATE_SUBSTITUTE=true go run ./cmd/apim-simulator
