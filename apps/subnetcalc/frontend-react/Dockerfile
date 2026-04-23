# syntax=docker/dockerfile:1.7

# Stage 1: Build
FROM --platform=$BUILDPLATFORM oven/bun:1.3.13-alpine AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

WORKDIR /app
ENV NODE_OPTIONS=--max-old-space-size=1024

# Copy package files for dependency installation
COPY ./frontend-react/package.json ./frontend-react/bun.lock ./frontend-react/bunfig.toml ./

# Install dependencies (uses lock file for reproducible builds)
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile

# Copy shared source used via TypeScript/Vite aliases
COPY ./shared-frontend/src /shared-frontend/src

# Copy source code
COPY ./frontend-react .

# Build application (Vite will embed environment variables)
RUN bun run build

FROM --platform=$BUILDPLATFORM golang:1.26.2-alpine3.23 AS runtime-config-builder

WORKDIR /src
ARG TARGETOS
ARG TARGETARCH
COPY ./scripts/runtime-config-entrypoint.go ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags='-s -w' -o /out/runtime-config-entrypoint runtime-config-entrypoint.go

# Stage 2: Production
FROM dhi.io/nginx:1.29.5-debian13

# Copy built files from builder
COPY --chown=65532:65532 --from=builder /app/dist /usr/share/nginx/html
COPY --from=runtime-config-builder /out/runtime-config-entrypoint /usr/local/bin/runtime-config-entrypoint

# Copy nginx configuration
COPY --chown=65532:65532 ./frontend-react/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=65532:65532 ./frontend-react/public/runtime-config.js /usr/share/nginx/html/runtime-config.js

# Expose port
EXPOSE 8080

USER 65532:65532
ENTRYPOINT ["/usr/local/bin/runtime-config-entrypoint"]
