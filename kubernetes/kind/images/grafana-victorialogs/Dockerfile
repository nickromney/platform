ARG PLUGIN_FETCH_IMAGE=docker.io/library/alpine:3.22
ARG GRAFANA_BASE_IMAGE=docker.io/grafana/grafana:12.3.1
ARG GRAFANA_IMAGE_TAG=12.3.1
FROM ${PLUGIN_FETCH_IMAGE} AS plugin

COPY victorialogs.zip /tmp/victorialogs.zip
RUN mkdir -p /tmp/plugins \
  && busybox unzip -q /tmp/victorialogs.zip -d /tmp/plugins \
  && rm -f /tmp/victorialogs.zip

FROM ${GRAFANA_BASE_IMAGE}

USER root
RUN mkdir -p /opt/grafana/plugins
COPY --from=plugin /tmp/plugins/victoriametrics-logs-datasource /opt/grafana/plugins/victoriametrics-logs-datasource
RUN chown -R grafana:root /opt/grafana/plugins
USER grafana
