FROM dhi.io/node:22.23.4-debian13@sha256:b2191eda91feb8bcc6a8c3a055651216ddfed8239bd29c8c5e9fbcf43227a1bc

ENV NODE_ENV=production
ENV HOME=/tmp

# Default matches the Backstage template's backendPort. Kubernetes sets PORT at runtime.
ARG PORT=8080
ENV PORT=${PORT}

WORKDIR /app

COPY package.json ./
COPY server.js ./

EXPOSE 8080

USER 1000:1000

CMD ["node", "server.js"]
