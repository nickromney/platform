FROM --platform=$BUILDPLATFORM oven/bun:1.3.10-alpine AS build

WORKDIR /app

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

# Guardrail: this UI must remain a static SPA (no React Server Components / Flight protocol).
# Fail the build if someone accidentally introduces Next.js or react-server-dom-* packages.
RUN bun pm ls >/tmp/deps.txt && \
    for pkg in next react-server-dom-webpack react-server-dom-turbopack react-server-dom-parcel react-server-dom-vite; do \
      if grep -Eq "^${pkg}@" /tmp/deps.txt; then \
        echo "ERROR: Disallowed dependency detected: $pkg (RSC/Flight-related)." >&2; \
        exit 1; \
      fi; \
    done

COPY index.html vite.config.js ./
COPY src ./src

ARG VITE_KEYCLOAK_BASE_URL
ENV VITE_KEYCLOAK_BASE_URL=$VITE_KEYCLOAK_BASE_URL

RUN bun run build

FROM dhi.io/nginx:1.29.5-debian13

COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080

USER nginx
