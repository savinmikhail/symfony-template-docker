#!/bin/sh
set -eu

backup_script=/usr/local/bin/postgres-backup.sh
cron_wrapper=/usr/local/bin/postgres-backup-cron.sh

write_cron_wrapper() {
  cat > "${cron_wrapper}" <<'EOF'
#!/bin/sh
set -eu

lock_dir=/tmp/postgres-backup.lock
if ! mkdir "${lock_dir}" 2>/dev/null; then
  printf '[postgres-backup] Previous backup is still running, skipping\n'
  exit 0
fi

cleanup() {
  rmdir "${lock_dir}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

exec /usr/local/bin/postgres-backup.sh
EOF
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
