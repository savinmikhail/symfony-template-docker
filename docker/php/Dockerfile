# syntax=docker/dockerfile:1.7

FROM php:8.4-fpm-alpine AS php-base

LABEL org.opencontainers.image.source="symfony-template-docker" \
      org.opencontainers.image.description="PHP-FPM 8.4 for Symfony applications" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /var/www/app

# System dependencies
RUN apk add --no-cache \
    bash \
    git \
    icu-dev \
    libpq-dev \
    libzip-dev \
    oniguruma-dev \
    tzdata \
    curl \
    zip \
    unzip

# Use mlocati/docker-php-extension-installer to install PHP extensions
COPY --from=mlocati/php-extension-installer:latest /usr/bin/install-php-extensions /usr/local/bin/

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        intl \
        opcache \
        pdo_pgsql \
        zip

# Copy Composer binary from official image
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Common PHP configuration (can be overridden in child stages)
RUN { \
        echo "memory_limit=512M"; \
        echo "upload_max_filesize=16M"; \
        echo "post_max_size=16M"; \
        echo "date.timezone=UTC"; \
        echo "opcache.enable=1"; \
        echo "opcache.enable_cli=1"; \
        echo "opcache.preload_user=www-data"; \
        echo "opcache.interned_strings_buffer=16"; \
        echo "opcache.max_accelerated_files=20000"; \
        echo "opcache.validate_timestamps=0"; \
    } > /usr/local/etc/php/conf.d/symfony.ini


# === Development image ===
FROM php-base AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1

# Helpful dev extensions/tools (xdebug etc.)
RUN install-php-extensions xdebug

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

CMD ["php-fpm"]

