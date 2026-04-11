ARG PYTHON_BUILD_IMAGE=dhi.io/python:3.13-debian13-dev
ARG PYTHON_RUNTIME_IMAGE=dhi.io/python:3.13-debian13
FROM ${PYTHON_BUILD_IMAGE} AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN python -m venv /app/.venv

ENV PATH="/app/.venv/bin:$PATH"

RUN pip install --no-cache-dir mcp==1.26.0

FROM ${PYTHON_RUNTIME_IMAGE}

ARG APP_UID=65532
ARG APP_GID=65532

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:/opt/python/bin:$PATH" \
    PORT=8080 \
    HOME=/tmp

WORKDIR /app

COPY --chown=${APP_UID}:${APP_GID} --from=builder /app/.venv /app/.venv
COPY --chown=${APP_UID}:${APP_GID} server.py .

EXPOSE 8080

USER ${APP_UID}:${APP_GID}

CMD ["python", "server.py"]
