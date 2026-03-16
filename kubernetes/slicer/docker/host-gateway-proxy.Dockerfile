FROM alpine:3.20

RUN apk add --no-cache socat

CMD ["sh", "-c", "exec socat TCP-LISTEN:${LISTEN_PORT:-443},fork,reuseaddr TCP:${UPSTREAM_HOST:-host.docker.internal}:${UPSTREAM_PORT:-8443}"]
