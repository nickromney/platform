.PHONY: test build build-linux clean

GO_APP_CMD ?= ./cmd/$(GO_APP_BINARY)
GO_APP_WEB_ASSETS ?=
GO_APP_STATIC_DIST_SOURCE ?= internal/app/web/.
GO_APP_STATIC_DIST_TARGET ?= .run/frontend-static

test:
	go test ./...

build:
	@mkdir -p .run
	go build -trimpath -ldflags="-s -w" -o .run/$(GO_APP_BINARY) $(GO_APP_CMD)

build-linux:
	@mkdir -p .run
	CGO_ENABLED=0 GOOS=linux GOARCH=$${GOARCH:-$(GO_APP_GOARCH)} go build -trimpath -ldflags="-s -w" -o .run/$(GO_APP_BINARY) $(GO_APP_CMD)

ifeq ($(GO_APP_WEB_ASSETS),)
else
.PHONY: js-check
js-check:
	biome check $(GO_APP_WEB_ASSETS)
	deno check --check-js internal/app/web/app.js
endif

ifeq ($(GO_APP_STATIC_DIST),1)
.PHONY: static-dist
static-dist:
	@rm -rf $(GO_APP_STATIC_DIST_TARGET)
	@mkdir -p $(GO_APP_STATIC_DIST_TARGET)
	cp -R $(GO_APP_STATIC_DIST_SOURCE) $(GO_APP_STATIC_DIST_TARGET)/
endif

clean:
	rm -rf .run
