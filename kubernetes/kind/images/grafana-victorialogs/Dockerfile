ARG PLUGIN_FETCH_IMAGE=docker.io/library/alpine:3.22
ARG GRAFANA_BASE_IMAGE=docker.io/grafana/grafana:12.3.1
ARG GRAFANA_IMAGE_TAG=12.3.1
FROM ${PLUGIN_FETCH_IMAGE} AS plugin

ARG VICTORIA_LOGS_PLUGIN_URL

RUN apk add --no-cache curl unzip
RUN mkdir -p /tmp/plugins \
  && curl -fsSL "${VICTORIA_LOGS_PLUGIN_URL}" -o /tmp/victorialogs.zip \
  && unzip -q /tmp/victorialogs.zip -d /tmp/plugins \
  && rm -f /tmp/victorialogs.zip

FROM ${GRAFANA_BASE_IMAGE}

USER root
RUN mkdir -p /opt/grafana/plugins
COPY --from=plugin /tmp/plugins/victoriametrics-logs-datasource /opt/grafana/plugins/victoriametrics-logs-datasource
RUN chown -R grafana:root /opt/grafana/plugins
USER grafana
