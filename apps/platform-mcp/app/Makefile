.PHONY: help test build build-linux run

PLATFORM_MCP_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

help:
	@echo "Platform MCP Go:"
	@echo "  test         Run Go unit tests"
	@echo "  build        Build the local binary at .run/platform-mcp"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run          Run the MCP server on port 8080"

test:
	go test ./...

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/platform-mcp ./cmd/platform-mcp

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(PLATFORM_MCP_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/platform-mcp ./cmd/platform-mcp

run:
	PORT=8080 go run ./cmd/platform-mcp
