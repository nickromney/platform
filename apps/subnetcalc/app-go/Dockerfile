FROM alpine:3.22

RUN addgroup -S -g 65532 subnetcalc \
    && adduser -S -D -H -u 65532 -G subnetcalc subnetcalc \
    && apk add --no-cache ca-certificates

COPY .run/subnetcalc /subnetcalc

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/subnetcalc"]
