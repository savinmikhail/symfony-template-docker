FROM alpine:3.21

RUN apk add --no-cache \
    postgresql16-client \
    rclone \
    tzdata

COPY docker/postgres-backup/backup.sh /usr/local/bin/postgres-backup.sh
COPY docker/postgres-backup/entrypoint.sh /usr/local/bin/postgres-backup-entrypoint.sh

RUN chmod 700 /usr/local/bin/postgres-backup.sh /usr/local/bin/postgres-backup-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/postgres-backup-entrypoint.sh"]
CMD ["crond"]
