FROM alpine:3.22

RUN addgroup -S -g 65532 sentiment \
    && adduser -S -D -H -u 65532 -G sentiment sentiment \
    && apk add --no-cache ca-certificates

COPY .run/sentiment /sentiment

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/sentiment"]
