FROM dhi.io/nginx:1.29.5-debian13

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

# Default matches the Backstage template's frontendPort. nginx.conf is rendered with the chosen port.
EXPOSE 8080

USER 65532:65532
