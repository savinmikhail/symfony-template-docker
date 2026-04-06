# syntax=docker/dockerfile:1.7

FROM php:8.4-fpm AS php-base

WORKDIR /var/www/app

# System dependencies
# kics-scan ignore-line
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash \
    git \
    tzdata \
    curl \
    libfcgi-bin \
    zip \
    unzip \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/www/app \
 && chown -R www-data:www-data /var/www/app

# Use mlocati/docker-php-extension-installer to install PHP extensions
COPY --from=mlocati/php-extension-installer:latest /usr/bin/install-php-extensions /usr/local/bin/

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        intl \
        opcache \
        pdo_pgsql \
        zip \
        redis \
        amqp

# Copy Composer binary from official image
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Default PHP-FPM configuration (can be overridden with volumes)
COPY docker/php/conf/php.ini /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/php/conf/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY docker/php/conf/www.conf /usr/local/etc/php-fpm.d/www.conf


# === Development image ===
FROM php-base AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1 \
    COMPOSER_HOME=/tmp/composer

ARG HOST_UID=1000
ARG HOST_GID=1000

# Helpful dev extensions/tools (xdebug etc.)
RUN install-php-extensions xdebug

RUN groupmod -o -g "${HOST_GID}" www-data \
 && usermod -o -u "${HOST_UID}" -g "${HOST_GID}" www-data \
 && mkdir -p /tmp/composer \
 && chown -R www-data:www-data /tmp/composer

USER www-data

# By default we expect project code to be mounted as a volume
CMD ["php-fpm"]


# === Build image for production (composer install, cache warmup) ===
FROM php-base AS build

ENV APP_ENV=prod \
    APP_DEBUG=0

# Install PHP dependencies without dev packages
COPY app/composer.json app/composer.lock ./ 

RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-progress \
    --no-interaction \
    --no-scripts

# Copy application source
COPY app ./ 

# Optimize autoloader and warm up Symfony cache
RUN composer dump-autoload --classmap-authoritative --no-dev && \
    php bin/console cache:clear --env=prod --no-warmup && \
    php bin/console cache:warmup --env=prod


# === Production runtime image ===
FROM php-base AS prod

ENV APP_ENV=prod \
    APP_DEBUG=0

COPY --from=build /var/www/app /var/www/app

RUN chown -R www-data:www-data /var/www/app

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD SCRIPT_NAME=/fpm-ping SCRIPT_FILENAME=/fpm-ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep -q "pong" || exit 1

USER www-data

CMD ["php-fpm"]
