FROM nginx:1.27-alpine
COPY default.conf.template /etc/nginx/templates/default.conf.template
ENV NGINX_PORT=80 \
    WEB_HOST=web \
    WEB_PORT=8080
EXPOSE 80
