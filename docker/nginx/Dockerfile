# syntax=docker/dockerfile:1.7

FROM nginx:1.27-alpine AS prod

COPY app/public /var/www/app/public
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/conf.d /etc/nginx/conf.d

RUN rm -f /etc/nginx/conf.d/default.conf \
    && sed -i '/^user  nginx;$/d' /etc/nginx/nginx.conf \
    && chown -R nginx:nginx /var/www/app

USER nginx
