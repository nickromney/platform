# Stage 1: Build
FROM --platform=$BUILDPLATFORM node:22-alpine AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM

WORKDIR /app

# Upgrade npm to latest version
RUN npm install -g npm@latest

# esbuild on Alpine can require glibc compatibility
RUN apk add --no-cache libc6-compat

# Build arguments for Vite environment variables
ARG VITE_AUTH_ENABLED=false
ARG VITE_JWT_USERNAME=
ARG VITE_JWT_PASSWORD=
ARG VITE_API_URL=http://localhost:8090

# Set as environment variables for Vite build
ENV VITE_AUTH_ENABLED=$VITE_AUTH_ENABLED
ENV VITE_JWT_USERNAME=$VITE_JWT_USERNAME
ENV VITE_JWT_PASSWORD=$VITE_JWT_PASSWORD
ENV VITE_API_URL=$VITE_API_URL

# Build shared-frontend (required for file:../shared-frontend dependency)
WORKDIR /shared-frontend
COPY ./shared-frontend/package.json ./shared-frontend/package-lock.json ./
RUN npm ci
COPY ./shared-frontend ./
RUN npm run build

WORKDIR /app

# Copy package files for dependency installation
COPY ./frontend-typescript-vite/package.json ./frontend-typescript-vite/package-lock.json ./

# Install dependencies (uses lock file for reproducible builds)
RUN npm ci

# Copy source code
COPY ./frontend-typescript-vite .

# Build application (Vite will embed environment variables)
RUN npm run build

# Stage 2: Production
FROM dhi.io/nginx:1.29.5-debian13

# Copy built files from builder
COPY --chown=nginx:nginx --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY --chown=nginx:nginx ./frontend-typescript-vite/nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 8080

# nginx starts automatically
