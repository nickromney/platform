.PHONY: help run-mcp run-shell

CHATGPT_LOCAL_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := chatgpt-sim
GO_APP_CMD := ./cmd/chatgpt-sim
GO_APP_GOARCH := $(CHATGPT_LOCAL_GOARCH)
GO_APP_WEB_ASSETS := internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html

help:
	@echo "ChatGPT Sim app:"
	@echo "  test         Run Go unit tests"
	@echo "  js-check     Run Biome and Deno checks for browser JavaScript"
	@echo "  build        Build the local binary at .run/chatgpt-sim"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run-mcp      Run the MCP role directly"
	@echo "  run-shell    Run the shell role directly"
	@echo "  clean        Remove generated .run artifacts"

run-mcp:
	ROLE=mcp PORT=18082 PUBLIC_BASE_URL=http://localhost:18082 go run ./cmd/chatgpt-sim

run-shell:
	ROLE=shell PORT=18083 MCP_URL=http://localhost:18082/mcp go run ./cmd/chatgpt-sim

include ../../../mk/go-app-core.mk
