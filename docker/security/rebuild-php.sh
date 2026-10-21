#!/bin/sh
# Temporary source rebuild until Docker Official Images publishes patched tags.
# Source checksums: docker-library/php e3eaff845f7a9f7259c31da54dce0320b47a3bbd.
set -eux
set -f
version="${1:?PHP version required}"
checksum="${2:?PHP source SHA256 required}"
php_api="$(php-config --extension-dir)"
php -m | sort > /tmp/php-modules-before
# php-config appends build environment values containing spaces after build_alias.
configure_options="$(php-config --configure-options | sed 's/ build_alias=.*//')"
if command -v apk >/dev/null 2>&1; then
    sed -i 's|https://dl-cdn.alpinelinux.org/alpine|https://dl-4.alpinelinux.org/alpine|g' /etc/apk/repositories
    printf 'timeout 60\n' > /etc/apk/config
    apk add --no-cache --virtual .php-security-build-deps $PHPIZE_DEPS \
        argon2-dev coreutils curl-dev gnu-libiconv-dev libsodium-dev libxml2-dev \
        linux-headers oniguruma-dev openssl-dev readline-dev sqlite-dev
    rm -f /usr/include/iconv.h
else
    sed -i -e 's|http://deb.debian.org/debian-security|https://security.debian.org/debian-security|g' -e 's|http://deb.debian.org/debian|https://mirrors.kernel.org/debian|g' /etc/apt/sources.list.d/debian.sources
    printf 'Acquire::EnableSrvRecords "false";\nAcquire::ForceIPv4 "true";\nAcquire::Retries "3";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAPT::Update::Error-Mode "any";\n' > /etc/apt/apt.conf.d/80-network-retries
    saved_apt_mark="$(apt-mark showmanual)"
    apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=2 update
    apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=2 install -y --no-install-recommends \
        $PHPIZE_DEPS libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev \
        libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev
fi
curl --fail --location --retry 3 --connect-timeout 30 --max-time 300 \
    "https://www.php.net/distributions/php-$version.tar.xz" -o /usr/src/php-security.tar.xz
printf '%s  %s\n' "$checksum" /usr/src/php-security.tar.xz | sha256sum -c -
docker-php-source delete
mv /usr/src/php-security.tar.xz /usr/src/php.tar.xz
docker-php-source extract
cd /usr/src/php
export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"
export PHP_BUILD_PROVIDER='https://github.com/docker-library/php' PHP_UNAME='Linux - Docker'
# Options come exclusively from the pinned Docker Official PHP base.
# shellcheck disable=SC2086
./configure $configure_options
make -j "${PHP_SECURITY_BUILD_JOBS:-2}"
make install
find /usr/local -type f -name '*.a' -delete
cd /
docker-php-source delete
if command -v apk >/dev/null 2>&1; then
    apk del --no-network .php-security-build-deps
else
    apt-mark auto '.*' >/dev/null
    # shellcheck disable=SC2086
    apt-mark manual $saved_apt_mark >/dev/null
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
    rm -rf /var/lib/apt/lists/*
fi
test "$(php -r 'echo PHP_VERSION;')" = "$version"
test "$(php-config --extension-dir)" = "$php_api"
php -m | sort > /tmp/php-modules-after
diff -u /tmp/php-modules-before /tmp/php-modules-after
rm /tmp/php-modules-before /tmp/php-modules-after
php --version
