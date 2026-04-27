FROM dhi.io/node:22-debian13

ENV NODE_ENV=production
ENV PORT=${{ values.backendPort }}
ENV HOME=/tmp

WORKDIR /app

COPY package.json ./
COPY server.js ./

EXPOSE ${{ values.backendPort }}

USER 1000:1000

CMD ["node", "server.js"]

