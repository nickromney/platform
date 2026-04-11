ARG NGINX_RUNTIME_IMAGE=dhi.io/nginx:1.29.5-debian13
FROM node:22-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json .npmrc ./
RUN npm ci

COPY . .
RUN npm run build

FROM --platform=$BUILDPLATFORM golang:1.26.1-alpine3.23 AS runtime-config-builder

WORKDIR /src
ARG TARGETOS
ARG TARGETARCH
COPY scripts/runtime-config-entrypoint.go ./
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags='-s -w' -o /out/runtime-config-entrypoint runtime-config-entrypoint.go

FROM ${NGINX_RUNTIME_IMAGE}

ARG NGINX_UID=101
ARG NGINX_GID=101

COPY --chown=${NGINX_UID}:${NGINX_GID} nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=${NGINX_UID}:${NGINX_GID} --from=builder /app/dist /usr/share/nginx/html
COPY --from=runtime-config-builder /out/runtime-config-entrypoint /usr/local/bin/runtime-config-entrypoint

EXPOSE 8080

USER ${NGINX_UID}:${NGINX_GID}

ENTRYPOINT ["/usr/local/bin/runtime-config-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
