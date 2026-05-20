FROM dhi.io/static:20260413-alpine3.23

COPY .run/chatgpt-sim /chatgpt-sim

USER 65532:65532
ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/chatgpt-sim"]
