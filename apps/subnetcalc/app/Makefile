.PHONY: help run-backend run-frontend

SUBNETCALC_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := subnetcalc
GO_APP_CMD := ./cmd/subnetcalc
GO_APP_GOARCH := $(SUBNETCALC_GOARCH)
GO_APP_WEB_ASSETS := internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html
GO_APP_STATIC_DIST := 1

help:
	@echo "Subnetcalc app:"
	@echo "  test          Run Go unit tests"
	@echo "  js-check      Check vanilla JavaScript source contracts"
	@echo "  build         Build the local binary at .run/subnetcalc"
	@echo "  build-linux   Build the Linux binary used by compose/kind images"
	@echo "  static-dist   Copy embedded web assets to .run/frontend-static"
	@echo "  run-backend   Run the backend role directly on port 8090"
	@echo "  run-frontend  Run the frontend role directly on port 8003"
	@echo "  clean         Remove generated .run artifacts"

run-backend: ## Run the backend role directly on port 8090
	RUNTIME_ROLE=backend PORT=8090 go run ./cmd/subnetcalc

run-frontend: ## Run the frontend role directly on port 8003
	RUNTIME_ROLE=frontend BACKEND_URL=http://127.0.0.1:8090 PORT=8003 go run ./cmd/subnetcalc

include ../../../mk/go-app-core.mk
