.PHONY: test build build-linux static-dist run-backend run-frontend

SUBNETCALC_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

test:
	go test ./...

build:
	go build -trimpath -ldflags="-s -w" -o .run/subnetcalc ./cmd/subnetcalc

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(SUBNETCALC_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/subnetcalc ./cmd/subnetcalc

static-dist:
	@rm -rf .run/frontend-static
	@mkdir -p .run/frontend-static
	cp -R internal/app/web/. .run/frontend-static/

run-backend:
	RUNTIME_ROLE=backend PORT=8090 go run ./cmd/subnetcalc

run-frontend:
	RUNTIME_ROLE=frontend BACKEND_URL=http://127.0.0.1:8090 PORT=8003 go run ./cmd/subnetcalc
