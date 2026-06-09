.PHONY: help test js-check build build-linux run-mcp run-shell clean

CHATGPT_LOCAL_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

help:
	@echo "ChatGPT Sim app:"
	@echo "  test         Run Go unit tests"
	@echo "  js-check     Run Biome and Deno checks for browser JavaScript"
	@echo "  build        Build the local binary at .run/chatgpt-sim"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run-mcp      Run the MCP role directly"
	@echo "  run-shell    Run the shell role directly"
	@echo "  clean        Remove generated .run artifacts"

test:
	go test ./...

js-check:
	biome check internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html
	deno check --check-js internal/app/web/app.js

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/chatgpt-sim ./cmd/chatgpt-sim

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(CHATGPT_LOCAL_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/chatgpt-sim ./cmd/chatgpt-sim

run-mcp:
	ROLE=mcp PORT=18082 PUBLIC_BASE_URL=http://localhost:18082 go run ./cmd/chatgpt-sim

run-shell:
	ROLE=shell PORT=18083 MCP_URL=http://localhost:18082/mcp go run ./cmd/chatgpt-sim

clean:
	rm -rf .run
