# syntax=docker/dockerfile:1.7

FROM dhi.io/static:20260413-alpine3.23

WORKDIR /app

ENV HOME=/tmp \
    IDP_CATALOG_PATH=/app/catalog/platform-apps.json \
    PORT=8080

COPY --chown=65532:65532 apps/idp-core/app-go/.run/idp-core /usr/local/bin/idp-core
COPY --chown=65532:65532 catalog/platform-apps.json ./catalog/platform-apps.json

EXPOSE 8080

USER 65532:65532

ENTRYPOINT ["/usr/local/bin/idp-core"]
