.PHONY: help test build build-linux static-dist run-backend run-frontend

SUBNETCALC_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

help:
	@echo "App Go:"
	@echo "  test          Run Go unit tests"
	@echo "  build         Build the local binary at .run/subnetcalc"
	@echo "  build-linux   Build the Linux binary used by compose"
	@echo "  static-dist   Copy embedded web assets to .run/frontend-static"
	@echo "  run-backend   Run the backend role directly on port 8090"
	@echo "  run-frontend  Run the frontend role directly on port 8003"

test: ## Run Go unit tests
	go test ./...

build: ## Build the local binary at .run/subnetcalc
	go build -trimpath -ldflags="-s -w" -o .run/subnetcalc ./cmd/subnetcalc

build-linux: ## Build the Linux binary used by compose
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(SUBNETCALC_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/subnetcalc ./cmd/subnetcalc

static-dist: ## Copy embedded web assets to .run/frontend-static
	@rm -rf .run/frontend-static
	@mkdir -p .run/frontend-static
	cp -R internal/app/web/. .run/frontend-static/

run-backend: ## Run the backend role directly on port 8090
	RUNTIME_ROLE=backend PORT=8090 go run ./cmd/subnetcalc

run-frontend: ## Run the frontend role directly on port 8003
	RUNTIME_ROLE=frontend BACKEND_URL=http://127.0.0.1:8090 PORT=8003 go run ./cmd/subnetcalc
