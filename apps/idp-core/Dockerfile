# syntax=docker/dockerfile:1.7

FROM alpine:3.22

RUN addgroup -S -g 65532 idp-core \
    && adduser -S -D -H -u 65532 -G idp-core idp-core \
    && apk add --no-cache ca-certificates

WORKDIR /app

ENV HOME=/tmp \
    IDP_CATALOG_PATH=/app/catalog/platform-apps.json \
    PORT=8080

COPY --chown=65532:65532 apps/idp-core/app-go/.run/idp-core /usr/local/bin/idp-core
COPY --chown=65532:65532 catalog/platform-apps.json ./catalog/platform-apps.json

EXPOSE 8080

USER 65532:65532

ENTRYPOINT ["/usr/local/bin/idp-core"]
