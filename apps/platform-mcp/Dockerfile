# syntax=docker/dockerfile:1.7

FROM dhi.io/python:3.13-debian13-dev AS builder

COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

WORKDIR /app
COPY apps/platform-mcp/pyproject.toml apps/platform-mcp/uv.lock ./
COPY apps/platform-mcp/platform_mcp ./platform_mcp
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --link-mode=copy --no-dev

FROM dhi.io/python:3.13-debian13-dev AS d2
ARG D2_VERSION=0.7.1
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gzip tar \
    && rm -rf /var/lib/apt/lists/* \
    && case "${TARGETARCH:-amd64}" in \
        amd64) D2_ARCH=amd64; D2_SHA256=eb172adf59f38d1e5a70ab177591356754ffaf9bebb84e0ca8b767dfb421dad7 ;; \
        arm64) D2_ARCH=arm64; D2_SHA256=ce3a0b985a8f91335a826c254b3a88736fd81afcdd08b58f6c749d2add6864b0 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/terrastruct/d2/releases/download/v${D2_VERSION}/d2-v${D2_VERSION}-linux-${D2_ARCH}.tar.gz" -o /tmp/d2.tar.gz \
    && echo "${D2_SHA256}  /tmp/d2.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/local/bin \
    && tar -xzf /tmp/d2.tar.gz -C /usr/local/bin --strip-components=2 d2-v${D2_VERSION}/bin/d2 \
    && rm -f /tmp/d2.tar.gz

FROM dhi.io/python:3.13-debian13 AS runtime

WORKDIR /app
ENV PATH="/app/.venv/bin:/opt/python/bin:/usr/local/bin:$PATH" \
    HOME=/tmp \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    D2_BINARY=/usr/local/bin/d2 \
    PORT=8080

COPY --from=builder --chown=65532:65532 /app/.venv /app/.venv
COPY --from=builder --chown=65532:65532 /app/platform_mcp /app/platform_mcp
COPY --from=d2 /usr/local/bin/d2 /usr/local/bin/d2

USER 65532:65532
EXPOSE 8080
CMD ["/app/.venv/bin/platform-mcp"]
