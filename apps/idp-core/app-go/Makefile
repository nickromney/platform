.PHONY: build build-linux test clean

BINARY := .run/idp-core
IDP_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

build:
	mkdir -p .run
	go build -o $(BINARY) ./cmd/idp-core

build-linux:
	mkdir -p .run
	GOOS=linux GOARCH=$${GOARCH:-$(IDP_GOARCH)} CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o $(BINARY) ./cmd/idp-core

test:
	go test ./...

clean:
	rm -rf .run
