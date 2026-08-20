FROM dhi.io/node:22-debian13

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
