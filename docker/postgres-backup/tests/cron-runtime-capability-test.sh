#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
test_image_name="$(basename "$root_dir")-postgres-backup-test"
if [ -n "${GITHUB_RUN_ID:-}" ]; then
  test_image_name="${test_image_name}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
fi
backup_image=${POSTGRES_BACKUP_TEST_IMAGE:-${test_image_name}}

docker build \
  --quiet \
  --tag "${backup_image}" \
  --file "${root_dir}/docker/postgres-backup/Dockerfile" \
  "${root_dir}" >/dev/null

image_tag_variables=$(sed -nE 's/.*\$\{([A-Z_][A-Z0-9_]*_IMAGE_TAG)(:[^}]*)?\}.*/\1/p' \
  "${root_dir}/docker-compose.yml" "${root_dir}/docker-compose.prod.yml" | sort -u)
for variable in ${image_tag_variables}; do
  export "${variable}=test"
done

docker compose \
  --file "${root_dir}/docker-compose.yml" \
  --file "${root_dir}/docker-compose.prod.yml" \
  config \
  --format json \
  | jq -e '
      .services["postgres-backup"].cap_drop == ["ALL"]
      and .services["postgres-backup"].cap_add == ["SETGID"]
    ' >/dev/null

docker run --rm \
  --cap-drop ALL \
  --cap-add SETGID \
  --security-opt no-new-privileges:true \
  --entrypoint sh \
  "${backup_image}" \
  -c '
    set -eu
    test_dir=/tmp/postgres-backup-cron-test
    marker=/tmp/postgres-backup-cron-ran
    mkdir -p "${test_dir}"
    printf "@reboot /bin/touch %s\n" "${marker}" > "${test_dir}/root"
    chmod 600 "${test_dir}/root"

    crond -f -l 2 -c "${test_dir}" &
    cron_pid=$!
    trap "kill ${cron_pid} 2>/dev/null || true" EXIT INT TERM

    attempt=1
    while [ "${attempt}" -le 20 ]; do
      if [ -f "${marker}" ]; then
        kill "${cron_pid}" 2>/dev/null || true
        wait "${cron_pid}" 2>/dev/null || true
        trap - EXIT INT TERM
        echo "Cron runtime capability test passed."
        exit 0
      fi

      sleep 0.25
      attempt=$((attempt + 1))
    done

    echo "Cron did not start the scheduled root job." >&2
    exit 1
  '
