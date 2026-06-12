.PHONY: help run

IDP_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := idp-core
GO_APP_CMD := ./cmd/idp-core
GO_APP_GOARCH := $(IDP_GOARCH)

help:
	@echo "IDP Core app:"
	@echo "  test         Run Go unit tests"
	@echo "  build        Build the local binary at .run/idp-core"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run          Run the API on port 8080"
	@echo "  clean        Remove generated .run artifacts"

run:
	PORT=8080 go run ./cmd/idp-core

include ../../../mk/go-app-core.mk
