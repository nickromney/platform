FROM oven/bun:1.3.10 AS deps

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

FROM oven/bun:1.3.10 AS preload

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json config.js preload-model.js server.js telemetry.js ./

ENV NODE_ENV=production
ENV SENTIMENT_MODEL_CACHE_DIR=/opt/transformers-cache

RUN mkdir -p "${SENTIMENT_MODEL_CACHE_DIR}"
RUN node preload-model.js

FROM dhi.io/node:22-debian13

WORKDIR /app

COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node --from=preload /opt/transformers-cache /opt/transformers-cache
COPY --chown=node:node package.json config.js server.js telemetry.js ./

ENV NODE_ENV=production
ENV PORT=8080
ENV SENTIMENT_MODEL_CACHE_DIR=/opt/transformers-cache
ENV SENTIMENT_MODEL_LOCAL_ONLY=1

USER node

EXPOSE 8080

CMD ["node", "server.js"]
