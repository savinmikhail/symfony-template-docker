# KICS: crond must start as root to install and run the generated backup schedule.
# kics-scan ignore-line
FROM alpine:3.21

ARG ALPINE_MIRROR=https://dl-4.alpinelinux.org/alpine
RUN sed -i "s|https://dl-cdn.alpinelinux.org/alpine|${ALPINE_MIRROR}|g" /etc/apk/repositories \
    && apk add --no-cache \
    postgresql16-client \
    rclone \
    tzdata

COPY docker/postgres-backup/backup.sh /usr/local/bin/postgres-backup.sh
COPY docker/postgres-backup/entrypoint.sh /usr/local/bin/postgres-backup-entrypoint.sh

RUN chmod 700 /usr/local/bin/postgres-backup.sh /usr/local/bin/postgres-backup-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/postgres-backup-entrypoint.sh"]
CMD ["crond"]
