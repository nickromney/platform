FROM dhi.io/static:20260413-alpine3.23

COPY --chown=65532:65532 app/.run/apim-simulator /apim-simulator
COPY examples /app/examples

USER 65532:65532
ENV PORT=8000 \
    HOME=/tmp
EXPOSE 8000

ENTRYPOINT ["/apim-simulator"]
