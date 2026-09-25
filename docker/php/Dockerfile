# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e

FROM php:8.4.25-fpm-trixie@sha256:223115611852f585846b5d30f0cd95de8af9b486ca3bf310174a143704fc71e3 AS php-runtime

WORKDIR /var/www/app

# Runtime packages needed by the image, including the FPM health check.
# kics-scan ignore-line
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    tzdata \
    libfcgi-bin \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/www/app \
 && chown -R www-data:www-data /var/www/app

# Use a versioned, immutable multi-platform extension installer.
COPY --from=mlocati/php-extension-installer:2.12.0@sha256:1afade3e29cfc97362cf5885e5ac333bf2faab1146cb28ebbb59b17e68f87e88 /usr/bin/install-php-extensions /usr/local/bin/

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        intl \
        opcache \
        pdo_pgsql \
        zip \
        redis \
        amqp && \
    rm -f /usr/local/bin/install-php-extensions

# Default PHP-FPM configuration (can be overridden with volumes)
COPY docker/php/conf/php.ini /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/php/conf/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY docker/php/conf/www.conf /usr/local/etc/php-fpm.d/www.conf

# Build and development tools live only in non-runtime targets.
FROM php-runtime AS php-tooling

ENV COMPOSER_HOME=/tmp/composer

# kics-scan ignore-line
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    zip \
    unzip \
 && rm -rf /var/lib/apt/lists/*

# Composer is versioned and pinned to its immutable multi-platform manifest.
COPY --from=composer:2.10.3@sha256:9715c7f69044da2a212a5fbde29ee7da24e364d426560ae6367b060236f847d7 /usr/bin/composer /usr/bin/composer


# === Development image ===
FROM php-tooling AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1 \
    COMPOSER_HOME=/tmp/composer

ARG HOST_UID=1000
ARG HOST_GID=1000

# Pin the PECL extension too, so the dev layer does not drift on rebuild.
COPY --from=mlocati/php-extension-installer:2.12.0@sha256:1afade3e29cfc97362cf5885e5ac333bf2faab1146cb28ebbb59b17e68f87e88 /usr/bin/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions xdebug-3.5.3 && \
    rm -f /usr/local/bin/install-php-extensions

RUN groupmod -o -g "${HOST_GID}" www-data \
 && usermod -o -u "${HOST_UID}" -g "${HOST_GID}" www-data \
 && mkdir -p /tmp/composer \
 && chown -R www-data:www-data /tmp/composer

USER www-data

# By default we expect project code to be mounted as a volume
CMD ["php-fpm"]


# === Self-contained image for CI (application code + development dependencies) ===
FROM php-tooling AS ci

ENV APP_ENV=test \
    APP_DEBUG=1 \
    COMPOSER_HOME=/tmp/composer

# Keep the expensive dependency layer independent from application source changes.
COPY app/composer.json app/composer.lock ./
COPY app/tools/composer-dependency-analyser/composer.json app/tools/composer-dependency-analyser/composer.lock ./tools/composer-dependency-analyser/
COPY app/tools/php-cs-fixer/composer.json app/tools/php-cs-fixer/composer.lock ./tools/php-cs-fixer/
COPY app/tools/phpat/composer.json app/tools/phpat/composer.lock ./tools/phpat/
COPY app/tools/phpstan/composer.json app/tools/phpstan/composer.lock ./tools/phpstan/
COPY app/tools/rector/composer.json app/tools/rector/composer.lock ./tools/rector/

RUN composer install --prefer-dist --no-progress --no-interaction --no-scripts

COPY app ./

RUN composer dump-autoload --no-interaction \
 && mkdir -p /tmp/composer \
 && chown -R www-data:www-data /var/www/app /tmp/composer

USER www-data

CMD ["php-fpm"]


# === Stable production dependencies (invalidated by Composer manifests) ===
FROM php-tooling AS prod-dependencies

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


# === Build image for production (application source, autoload, cache warmup) ===
FROM prod-dependencies AS build

# Copy application source
COPY app ./ 

# Optimize autoloader and warm up Symfony cache
RUN composer dump-autoload --classmap-authoritative --no-dev && \
    php bin/console cache:clear --env=prod --no-warmup && \
    php bin/console cache:warmup --env=prod


# === Production runtime image ===
FROM php-runtime AS prod

ENV APP_ENV=prod \
    APP_DEBUG=0

COPY --chown=www-data:www-data --from=build /var/www/app /var/www/app

RUN install -d -o www-data -g www-data /var/www/app/var/metrics

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD SCRIPT_NAME=/fpm-ping SCRIPT_FILENAME=/fpm-ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 | grep -q "pong" || exit 1

USER www-data

CMD ["php-fpm"]
