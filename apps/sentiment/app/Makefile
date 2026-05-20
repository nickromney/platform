.PHONY: test js-check build build-linux static-dist run-backend run-frontend

SENTIMENT_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

test:
	go test ./...

js-check:
	biome check internal/app/web/app.js internal/app/web/api-types.d.ts
	deno check --check-js internal/app/web/app.js

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/sentiment ./cmd/sentiment

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(SENTIMENT_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/sentiment ./cmd/sentiment

static-dist:
	@rm -rf .run/frontend-static
	@mkdir -p .run/frontend-static
	cp -R internal/app/web/. .run/frontend-static/

run-backend:
	RUNTIME_ROLE=backend PORT=8306 DATA_DIR=.run/data go run ./cmd/sentiment

run-frontend:
	RUNTIME_ROLE=frontend BACKEND_URL=http://127.0.0.1:8306 PORT=8307 go run ./cmd/sentiment
