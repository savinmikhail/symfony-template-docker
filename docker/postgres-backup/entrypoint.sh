#!/bin/sh
set -eu

backup_script=/usr/local/bin/postgres-backup.sh
cron_wrapper=/usr/local/bin/postgres-backup-cron-run.sh

shell_quote() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

write_cron_wrapper() {
  {
    echo '#!/bin/sh'
    echo 'set -eu'

    for var_name in \
      POSTGRES_HOST \
      POSTGRES_PORT \
      POSTGRES_DB \
      POSTGRES_USER \
      POSTGRES_PASSWORD \
      POSTGRES_BACKUP_DIR \
      POSTGRES_BACKUP_KEEP_DAYS \
      POSTGRES_BACKUP_PREFIX \
      POSTGRES_BACKUP_NAME \
      POSTGRES_BACKUP_METRICS_DIR \
      POSTGRES_BACKUP_S3_ENABLED \
      POSTGRES_BACKUP_S3_ENDPOINT \
      POSTGRES_BACKUP_S3_REGION \
      POSTGRES_BACKUP_S3_BUCKET \
      POSTGRES_BACKUP_S3_ACCESS_KEY \
      POSTGRES_BACKUP_S3_SECRET_KEY \
      POSTGRES_BACKUP_S3_PREFIX \
      POSTGRES_BACKUP_S3_KEEP_DAYS \
      POSTGRES_BACKUP_S3_PATH_STYLE \
      TZ
    do
      eval "value=\${$var_name-}"
      printf "%s='%s'\n" "$var_name" "$(shell_quote "${value}")"
      printf "export %s\n" "$var_name"
    done

    printf "exec %s\n" "${backup_script}"
  } > "${cron_wrapper}"

  chmod 700 "${cron_wrapper}"
}

run_mode=${1:-crond}

case "${run_mode}" in
  backup-once)
    exec "${backup_script}"
    ;;
  crond|'')
    write_cron_wrapper
    schedule=${POSTGRES_BACKUP_CRON:-17 3 * * *}
    printf '%s %s >> /proc/1/fd/1 2>> /proc/1/fd/2\n' "${schedule}" "${cron_wrapper}" > /etc/crontabs/root
    printf '[postgres-backup] Installed cron schedule: %s\n' "${schedule}"

    if [ "${POSTGRES_BACKUP_RUN_ON_START:-0}" = "1" ]; then
      printf '[postgres-backup] Running startup backup\n'
      "${backup_script}"
    fi

    exec crond -f -l 2 -c /etc/crontabs
    ;;
  *)
    exec "$@"
    ;;
esac
