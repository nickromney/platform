FROM dhi.io/static:20260413-alpine3.23

COPY --chown=65532:65532 .run/chatgpt-sim /chatgpt-sim

USER 65532:65532
ENV PORT=8080 \
    HOME=/tmp
EXPOSE 8080

ENTRYPOINT ["/chatgpt-sim"]
