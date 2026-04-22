FROM --platform=$BUILDPLATFORM oven/bun:1.3.12-alpine AS build

WORKDIR /app

COPY package.json bun.lock bunfig.toml ./
RUN bun install --frozen-lockfile

# Guardrail: this UI must remain a small static SPA without React/Next baggage.
RUN bun pm ls >/tmp/deps.txt && \
    for pkg in react react-dom @vitejs/plugin-react next react-server-dom-webpack react-server-dom-turbopack react-server-dom-parcel react-server-dom-vite; do \
      if grep -Eq "^${pkg}@" /tmp/deps.txt; then \
        echo "ERROR: Disallowed dependency detected: $pkg." >&2; \
        exit 1; \
      fi; \
    done

COPY index.html vite.config.js tsconfig.json ./
COPY src ./src

ARG VITE_KEYCLOAK_BASE_URL
ENV VITE_KEYCLOAK_BASE_URL=$VITE_KEYCLOAK_BASE_URL

RUN bun run build

FROM dhi.io/nginx:1.29.5-debian13

COPY --chown=65532:65532 nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=65532:65532 --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080

USER 65532:65532
