# syntax=docker/dockerfile:1.7

FROM nginx:1.27-alpine AS prod

COPY app/public /var/www/app/public
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/conf.d /etc/nginx/conf.d
