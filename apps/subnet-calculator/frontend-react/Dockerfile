# Stage 1: Build
FROM --platform=$BUILDPLATFORM node:22-alpine AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

WORKDIR /app

# Upgrade npm to latest version
RUN npm install -g npm@latest
# esbuild on Alpine needs glibc compatibility
RUN apk add --no-cache libc6-compat

# Build arguments for Vite environment variables
ARG VITE_API_URL=http://localhost:7071
ARG VITE_API_PROXY_ENABLED=false
ARG VITE_AUTH_METHOD=none
ARG VITE_AZURE_CLIENT_ID=
ARG VITE_AZURE_TENANT_ID=common
ARG VITE_AZURE_REDIRECT_URI=
ARG VITE_JWT_USERNAME=
ARG VITE_JWT_PASSWORD=
ARG VITE_OIDC_AUTHORITY=
ARG VITE_OIDC_CLIENT_ID=
ARG VITE_OIDC_REDIRECT_URI=
ARG VITE_APIM_SUBSCRIPTION_KEY=
ARG VITE_OIDC_AUTO_LOGIN=false
ARG VITE_OIDC_PROMPT=
ARG VITE_OIDC_FORCE_REAUTH=false

# Set as environment variables for Vite build
ENV VITE_API_URL=$VITE_API_URL
ENV VITE_API_PROXY_ENABLED=$VITE_API_PROXY_ENABLED
ENV VITE_AUTH_METHOD=$VITE_AUTH_METHOD
ENV VITE_AZURE_CLIENT_ID=$VITE_AZURE_CLIENT_ID
ENV VITE_AZURE_TENANT_ID=$VITE_AZURE_TENANT_ID
ENV VITE_AZURE_REDIRECT_URI=$VITE_AZURE_REDIRECT_URI
ENV VITE_JWT_USERNAME=$VITE_JWT_USERNAME
ENV VITE_JWT_PASSWORD=$VITE_JWT_PASSWORD
ENV VITE_OIDC_AUTHORITY=$VITE_OIDC_AUTHORITY
ENV VITE_OIDC_CLIENT_ID=$VITE_OIDC_CLIENT_ID
ENV VITE_OIDC_REDIRECT_URI=$VITE_OIDC_REDIRECT_URI
ENV VITE_APIM_SUBSCRIPTION_KEY=$VITE_APIM_SUBSCRIPTION_KEY
ENV VITE_OIDC_AUTO_LOGIN=$VITE_OIDC_AUTO_LOGIN
ENV VITE_OIDC_PROMPT=$VITE_OIDC_PROMPT
ENV VITE_OIDC_FORCE_REAUTH=$VITE_OIDC_FORCE_REAUTH
ENV NODE_OPTIONS=--max-old-space-size=1024

# Build shared-frontend (required for file:../shared-frontend dependency)
WORKDIR /shared-frontend
COPY ./shared-frontend/package.json ./shared-frontend/package-lock.json ./
RUN npm ci
COPY ./shared-frontend ./
RUN npm run build

WORKDIR /app

# Copy package files for dependency installation
COPY ./frontend-react/package.json ./frontend-react/package-lock.json ./

# Install dependencies (uses lock file for reproducible builds)
RUN npm ci

# Copy source code
COPY ./frontend-react .

# Build application (Vite will embed environment variables)
RUN npm run build

# Stage 2: Production
FROM dhi.io/nginx:1.29.5-debian13

# Copy built files from builder
COPY --chown=nginx:nginx --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY --chown=nginx:nginx ./frontend-react/nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 8080

# nginx starts automatically
