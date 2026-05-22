.PHONY: help prereqs test build build-linux run-chat run-agent run-evals

LANGFUSE_DEMOS_LOCAL_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
LOCAL_OPENAI_BASE_URL ?= http://127.0.0.1:8000/v1

help:
	@echo "Langfuse demo apps:"
	@echo "  prereqs      Check Go plus the optional host oMLX OpenAI-compatible server"
	@echo "  test         Run Go unit tests"
	@echo "  build        Build the local binary at .run/langfuse-demos"
	@echo "  build-linux  Build the Linux binary used by kind images"
	@echo "  run-chat     Run the trace chat role"
	@echo "  run-agent    Run the tool agent role"
	@echo "  run-evals    Run the eval runner role"

prereqs:
	@set -euo pipefail; \
	command -v go >/dev/null 2>&1 || { echo "FAIL go (missing)"; exit 1; }; \
	echo "OK   go"; \
	base="$${LOCAL_OPENAI_BASE_URL:-$(LOCAL_OPENAI_BASE_URL)}"; \
	base="$${base%/}"; \
	echo "Local OpenAI-compatible model endpoint:"; \
	echo "  host endpoint: $$base"; \
	echo "  kind route: agentgateway -> host.docker.internal:8000"; \
	if command -v curl >/dev/null 2>&1; then \
		status="$$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "$$base/models" 2>/dev/null || true)"; \
		if [ "$$status" -ge 200 ] 2>/dev/null && [ "$$status" -lt 300 ]; then \
			echo "OK   oMLX $$base"; \
		elif [ "$$status" = "401" ] || [ "$$status" = "403" ]; then \
			echo "OK   oMLX $$base reachable but direct host probe returned HTTP $$status; gateway auth may still make the kind route usable."; \
		elif [ -n "$$status" ] && [ "$$status" != "000" ]; then \
			echo "WARN oMLX $$base returned HTTP $$status; start or fix the oMLX OpenAI-compatible server before expecting live LLM content."; \
		else \
			echo "WARN oMLX $$base is unreachable; start the oMLX OpenAI-compatible server before expecting live LLM content."; \
		fi; \
	else \
		echo "WARN curl missing; skipped oMLX endpoint probe."; \
	fi

test:
	go test ./...

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/langfuse-demos ./cmd/langfuse-demos

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(LANGFUSE_DEMOS_LOCAL_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/langfuse-demos ./cmd/langfuse-demos

run-chat:
	DEMO_ROLE=trace-chat PORT=18091 go run ./cmd/langfuse-demos

run-agent:
	DEMO_ROLE=tool-agent PORT=18092 go run ./cmd/langfuse-demos

run-evals:
	DEMO_ROLE=eval-runner PORT=18093 go run ./cmd/langfuse-demos
