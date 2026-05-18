# Dockerfile for static HTML frontend with nginx
FROM --platform=$BUILDPLATFORM golang:1.26.2-alpine3.23 AS runtime-config-builder

WORKDIR /src
ARG TARGETOS
ARG TARGETARCH
COPY ./scripts/runtime-config-entrypoint.go ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags='-s -w' -o /out/runtime-config-entrypoint runtime-config-entrypoint.go

FROM dhi.io/nginx:1.29.5-debian13

# Copy static HTML, CSS, JS files, and favicon
COPY --chown=65532:65532 ./frontend-html-static/index.html /usr/share/nginx/html/
COPY --chown=65532:65532 ./frontend-html-static/favicon.svg /usr/share/nginx/html/
COPY --chown=65532:65532 ./frontend-html-static/css/ /usr/share/nginx/html/css/
COPY --chown=65532:65532 ./frontend-html-static/js/ /usr/share/nginx/html/js/
COPY --from=runtime-config-builder /out/runtime-config-entrypoint /usr/local/bin/runtime-config-entrypoint

# Copy nginx template. The entrypoint renders the selected API upstream into
# /tmp/nginx.conf so one image can be used across backend matrix entries.
COPY --chown=65532:65532 ./frontend-html-static/nginx.conf.template /usr/share/nginx/templates/subnetcalc.conf.template

# Expose non-privileged HTTP port
EXPOSE 8081

USER 65532:65532
ENTRYPOINT ["/usr/local/bin/runtime-config-entrypoint"]
CMD ["nginx", "-c", "/tmp/nginx.conf", "-g", "daemon off;"]
