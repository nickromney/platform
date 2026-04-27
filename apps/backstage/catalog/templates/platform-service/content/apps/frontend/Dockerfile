FROM dhi.io/nginx:1.29.5-debian13

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE ${{ values.frontendPort }}

USER 65532:65532

