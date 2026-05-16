ARG NGINX_RUNTIME_IMAGE=dhi.io/nginx:1.29.5-debian13

FROM ${NGINX_RUNTIME_IMAGE}

ARG NGINX_UID=101
ARG NGINX_GID=101

COPY --chown=${NGINX_UID}:${NGINX_GID} nginx-main.conf /etc/nginx/nginx.conf
COPY --chown=${NGINX_UID}:${NGINX_GID} nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=${NGINX_UID}:${NGINX_GID} index.html app.js styles.css /usr/share/nginx/html/

EXPOSE 8080

USER ${NGINX_UID}:${NGINX_GID}

ENTRYPOINT ["nginx", "-g", "daemon off;"]
