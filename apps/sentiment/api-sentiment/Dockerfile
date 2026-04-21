FROM oven/bun:1.3.12 AS deps

WORKDIR /app

COPY package.json bun.lock bunfig.toml ./
RUN bun install --frozen-lockfile --production

FROM oven/bun:1.3.12 AS preload

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json config.js preload-model.js server.js telemetry.js comment-analysis-policy.js sentiment-label.js ./

ARG SENTIMENT_MODEL_ID
ENV NODE_ENV=production
ENV SENTIMENT_MODEL_CACHE_DIR=/opt/transformers-cache
ENV SENTIMENT_MODEL_ID=${SENTIMENT_MODEL_ID}

RUN mkdir -p "${SENTIMENT_MODEL_CACHE_DIR}"
RUN node preload-model.js

FROM dhi.io/node:22-debian13

WORKDIR /app

ARG SENTIMENT_MODEL_ID

COPY --chown=1000:1000 --from=deps /app/node_modules ./node_modules
COPY --chown=1000:1000 --from=preload /opt/transformers-cache /opt/transformers-cache
COPY --chown=1000:1000 package.json config.js server.js telemetry.js comment-analysis-policy.js sentiment-label.js ./

ENV NODE_ENV=production
ENV PORT=8080
ENV HOME=/tmp
ENV SENTIMENT_MODEL_CACHE_DIR=/opt/transformers-cache
ENV SENTIMENT_MODEL_ID=${SENTIMENT_MODEL_ID}
ENV SENTIMENT_MODEL_LOCAL_ONLY=1

USER 1000:1000

EXPOSE 8080

CMD ["node", "server.js"]
