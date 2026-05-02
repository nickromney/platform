.PHONY: build test fmt clean

BINARY_NAME ?= platform-tui
BIN_DIR ?= bin
GO ?= go

build:
	@mkdir -p "$(BIN_DIR)"
	$(GO) build -trimpath -o "$(BIN_DIR)/$(BINARY_NAME)" ./cmd/platform-tui

test:
	$(GO) test ./...

fmt:
	$(GO) fmt ./...
	$(GO) mod tidy

clean:
	rm -rf "$(BIN_DIR)"
