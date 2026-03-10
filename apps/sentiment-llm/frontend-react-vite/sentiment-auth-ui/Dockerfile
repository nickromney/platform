FROM node:22-alpine AS build

WORKDIR /app

COPY package.json ./
RUN npm install

# Guardrail: this UI must remain a static SPA (no React Server Components / Flight protocol).
# Fail the build if someone accidentally introduces Next.js or react-server-dom-* packages.
RUN for pkg in next react-server-dom-webpack react-server-dom-turbopack react-server-dom-parcel react-server-dom-vite; do \
      if npm ls "$pkg" >/dev/null 2>&1; then \
        echo "ERROR: Disallowed dependency detected: $pkg (RSC/Flight-related)." >&2; \
        exit 1; \
      fi; \
    done

COPY index.html vite.config.js ./
COPY src ./src

ARG VITE_KEYCLOAK_BASE_URL
ENV VITE_KEYCLOAK_BASE_URL=$VITE_KEYCLOAK_BASE_URL

RUN npm run build

FROM dhi.io/nginx:1.29.5-debian13

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080
