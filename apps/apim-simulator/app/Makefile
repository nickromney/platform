.PHONY: help run

APIM_SIMULATOR_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := apim-simulator
GO_APP_CMD := ./cmd/apim-simulator
GO_APP_GOARCH := $(APIM_SIMULATOR_GOARCH)
GO_APP_WEB_ASSETS := internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html

help:
	@echo "APIM Simulator app:"
	@echo "  test         Run Go unit tests"
	@echo "  js-check     Check vanilla JavaScript source contracts"
	@echo "  build        Build the local binary at .run/apim-simulator"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run          Run the simulator locally on port 8000"
	@echo "  clean        Remove generated .run artifacts"

run:
	PORT=8000 APIM_CONFIG_PATH=../examples/basic.json APIM_CONFIG_TEMPLATE_SUBSTITUTE=true go run ./cmd/apim-simulator

include ../../../mk/go-app-core.mk
