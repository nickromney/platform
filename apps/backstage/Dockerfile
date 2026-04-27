# syntax=docker/dockerfile:1.7

FROM node:22-bookworm-slim AS packages

WORKDIR /app

COPY package.json yarn.lock .yarnrc.yml backstage.json tsconfig.json ./
COPY .yarn ./.yarn
COPY packages ./packages
COPY plugins ./plugins

RUN find packages -mindepth 2 -maxdepth 2 ! -name package.json -exec rm -rf {} + && \
    find plugins -mindepth 2 -maxdepth 2 ! -name package.json -exec rm -rf {} +

FROM node:22-bookworm-slim AS deps

ENV NODE_OPTIONS="--no-node-snapshot"
ENV PYTHON=/usr/bin/python3
ENV COREPACK_HOME=/tmp/corepack
WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

RUN corepack enable

COPY --from=packages /app ./

RUN --mount=type=cache,target=/root/.cache/yarn,sharing=locked \
    yarn install --immutable

FROM deps AS build

COPY . .

RUN yarn tsc
RUN yarn build:backend

FROM node:22-bookworm-slim AS production-deps

ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"
ENV PYTHON=/usr/bin/python3
ENV COREPACK_HOME=/tmp/corepack
WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /tmp/corepack && \
    chown -R node:node /app /tmp/corepack

RUN corepack enable

USER node

COPY --chown=node:node --from=build /app/.yarn ./.yarn
COPY --chown=node:node --from=build /app/.yarnrc.yml /app/yarn.lock /app/package.json /app/backstage.json ./
COPY --chown=node:node --from=build /app/packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn workspaces focus --all --production && rm -rf "$(yarn cache clean)"

COPY --chown=node:node --from=build /app/catalog ./catalog
COPY --chown=node:node --from=build /app/app-config*.yaml ./
COPY --chown=node:node --from=build /app/packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

FROM dhi.io/node:22-debian13 AS runtime

ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"
ENV HOME=/tmp
ENV BACKSTAGE_BASE_URL=https://portal.127.0.0.1.sslip.io
WORKDIR /app

COPY --from=production-deps /usr/lib/aarch64-linux-gnu/libsqlite3.so.0* /usr/lib/aarch64-linux-gnu/
COPY --chown=1000:1000 --from=production-deps /app ./

EXPOSE 7007

USER 1000:1000

CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
