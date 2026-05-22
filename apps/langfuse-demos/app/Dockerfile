FROM dhi.io/static:20260413-alpine3.23

COPY .run/langfuse-demos /langfuse-demos

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/langfuse-demos"]
