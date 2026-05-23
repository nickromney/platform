.PHONY: help build build-linux test run clean

IDP_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

help:
	@echo "IDP Core app:"
	@echo "  test         Run Go unit tests"
	@echo "  build        Build the local binary at .run/idp-core"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run          Run the API on port 8080"
	@echo "  clean        Remove generated .run artifacts"

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/idp-core ./cmd/idp-core

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(IDP_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/idp-core ./cmd/idp-core

test:
	go test ./...

run:
	PORT=8080 go run ./cmd/idp-core

clean:
	rm -rf .run
