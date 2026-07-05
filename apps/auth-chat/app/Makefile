.PHONY: help run

AUTH_CHAT_LOCAL_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := auth-chat
GO_APP_CMD := ./cmd/auth-chat
GO_APP_GOARCH := $(AUTH_CHAT_LOCAL_GOARCH)
GO_APP_WEB_ASSETS := internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html internal/app/web/style.css

help:
	@echo "Auth Chat app:"
	@echo "  test         Run Go unit tests"
	@echo "  js-check     Run Biome and Deno checks for browser JavaScript"
	@echo "  build        Build the local binary at .run/auth-chat"
	@echo "  build-linux  Build the Linux binary used by kind images"
	@echo "  run          Run the app directly"
	@echo "  clean        Remove generated .run artifacts"

run:
	PORT=18086 PUBLIC_BASE_URL=http://localhost:18086 go run ./cmd/auth-chat

include ../../../mk/go-app-core.mk
