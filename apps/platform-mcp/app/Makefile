.PHONY: help run

PLATFORM_MCP_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := platform-mcp
GO_APP_CMD := ./cmd/platform-mcp
GO_APP_GOARCH := $(PLATFORM_MCP_GOARCH)

help:
	@echo "Platform MCP app:"
	@echo "  test         Run Go unit tests"
	@echo "  build        Build the local binary at .run/platform-mcp"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run          Run the MCP server on port 8080"
	@echo "  clean        Remove generated .run artifacts"

run:
	PORT=8080 go run ./cmd/platform-mcp

include ../../../mk/go-app-core.mk
