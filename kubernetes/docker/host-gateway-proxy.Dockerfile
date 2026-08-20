FROM alpine:3.22

# Alpine patch versions float with the 3.22 tag; socat is the only package.
# hadolint ignore=DL3018
RUN apk add --no-cache socat

CMD ["sh", "-c", "exec socat TCP-LISTEN:${LISTEN_PORT:-443},fork,reuseaddr TCP:${UPSTREAM_HOST:-host.docker.internal}:${UPSTREAM_PORT:-30070}"]
