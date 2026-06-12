.PHONY: help run-backend run-frontend

SENTIMENT_GOARCH ?= $(shell uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
GO_APP_BINARY := sentiment
GO_APP_CMD := ./cmd/sentiment
GO_APP_GOARCH := $(SENTIMENT_GOARCH)
GO_APP_WEB_ASSETS := internal/app/web/app.js internal/app/web/api-types.d.ts internal/app/web/index.html
GO_APP_STATIC_DIST := 1

help:
	@echo "Sentiment app:"
	@echo "  test          Run Go unit tests"
	@echo "  js-check      Check vanilla JavaScript source contracts"
	@echo "  build         Build the local binary at .run/sentiment"
	@echo "  build-linux   Build the Linux binary used by compose/kind images"
	@echo "  static-dist   Copy embedded web assets to .run/frontend-static"
	@echo "  run-backend   Run the backend role directly on port 8306"
	@echo "  run-frontend  Run the frontend role directly on port 8307"
	@echo "  clean         Remove generated .run artifacts"

run-backend:
	RUNTIME_ROLE=backend PORT=8306 DATA_DIR=.run/data go run ./cmd/sentiment

run-frontend:
	RUNTIME_ROLE=frontend BACKEND_URL=http://127.0.0.1:8306 PORT=8307 go run ./cmd/sentiment

include ../../../mk/go-app-core.mk
