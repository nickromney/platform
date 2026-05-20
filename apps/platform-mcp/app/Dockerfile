FROM dhi.io/static:20260413-alpine3.23

COPY .run/platform-mcp /platform-mcp

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/platform-mcp"]
