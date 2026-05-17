FROM dhi.io/static:20260413-alpine3.23

COPY .run/sentiment /sentiment

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/sentiment"]
