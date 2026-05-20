.PHONY: help build build-linux test run clean

BINARY := .run/idp-core
IDP_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

help:
	@echo "IDP Core app:"
	@echo "  test         Run Go unit tests"
	@echo "  build        Build the local binary at .run/idp-core"
	@echo "  build-linux  Build the Linux binary used by compose/kind images"
	@echo "  run          Run the API on port 8080"

build:
	mkdir -p .run
	go build -o $(BINARY) ./cmd/idp-core

build-linux:
	mkdir -p .run
	GOOS=linux GOARCH=$${GOARCH:-$(IDP_GOARCH)} CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o $(BINARY) ./cmd/idp-core

test:
	go test ./...

run:
	PORT=8080 go run ./cmd/idp-core

clean:
	rm -rf .run
