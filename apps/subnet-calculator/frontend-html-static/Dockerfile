# Dockerfile for static HTML frontend with nginx
FROM dhi.io/nginx:1.29.5-debian13

# Copy static HTML, CSS, JS files, and favicon
COPY --chown=65532:65532 index.html /usr/share/nginx/html/
COPY --chown=65532:65532 favicon.svg /usr/share/nginx/html/
COPY --chown=65532:65532 css/ /usr/share/nginx/html/css/
COPY --chown=65532:65532 js/ /usr/share/nginx/html/js/

# Copy nginx configuration
COPY --chown=65532:65532 nginx.conf /etc/nginx/conf.d/default.conf

# Expose non-privileged HTTP port
EXPOSE 8081

USER 65532:65532
