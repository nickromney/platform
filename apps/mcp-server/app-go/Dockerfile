FROM dhi.io/static:20260413-alpine3.23

COPY .run/mcp-server /mcp-server

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/mcp-server"]
