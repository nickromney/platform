FROM node:22-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:1.27-alpine

RUN apk add --no-cache gettext

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
COPY runtime-config.template.js /opt/runtime-config.template.js
COPY scripts/render-runtime-config.sh /docker-entrypoint.d/10-render-runtime-config.sh

RUN chmod +x /docker-entrypoint.d/10-render-runtime-config.sh

EXPOSE 8080
