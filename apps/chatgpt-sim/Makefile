.PHONY: test build build-linux run-mcp run-shell

CHATGPT_LOCAL_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

test:
	go test ./...

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/chatgpt-sim ./cmd/chatgpt-sim

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(CHATGPT_LOCAL_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/chatgpt-sim ./cmd/chatgpt-sim

run-mcp:
	ROLE=mcp PORT=18082 PUBLIC_BASE_URL=http://localhost:18082 go run ./cmd/chatgpt-sim

run-shell:
	ROLE=shell PORT=18083 MCP_URL=http://localhost:18082/mcp go run ./cmd/chatgpt-sim
