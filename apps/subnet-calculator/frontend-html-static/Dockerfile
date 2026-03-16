# Dockerfile for static HTML frontend with nginx
FROM dhi.io/nginx:1.29.5-debian13

# Copy static HTML, CSS, JS files, and favicon
COPY --chown=nginx:nginx index.html /usr/share/nginx/html/
COPY --chown=nginx:nginx favicon.svg /usr/share/nginx/html/
COPY --chown=nginx:nginx css/ /usr/share/nginx/html/css/
COPY --chown=nginx:nginx js/ /usr/share/nginx/html/js/

# Copy nginx configuration
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf

# Expose non-privileged HTTP port
EXPOSE 8081

USER nginx
