FROM oven/bun:1.3.10-alpine AS deps

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

FROM dhi.io/node:22-alpine3.22

WORKDIR /app

COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node package.json server.js telemetry.js ./

ENV NODE_ENV=production
ENV PORT=8080

EXPOSE 8080

USER node

CMD ["node", "server.js"]
