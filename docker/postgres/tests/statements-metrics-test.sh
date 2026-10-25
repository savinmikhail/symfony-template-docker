#!/bin/sh
# Real PostgreSQL 16 schema plus deterministic per-database metric aggregation.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
work=$(mktemp -d)
name="pg-statement-metrics-$(basename "$work" | tr '[:upper:]' '[:lower:]')"
cleanup() {
  docker rm -fv "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
sed -n '/^pg_stat_statements:/,/^  metrics:/p' "$root/docker/postgres/queries.yaml" | sed '1,2d;$d;s/^    //' > "$work/query.sql"
test -s "$work/query.sql"
docker run -d --rm --name "$name" --network none --tmpfs /var/lib/postgresql/data:rw,size=256m \
  -e POSTGRES_PASSWORD=isolated-fixture-only -e POSTGRES_DB=collector_fixture \
  "${POSTGRES_TEST_IMAGE:-postgres:16-alpine}" \
  -c shared_preload_libraries=pg_stat_statements >/dev/null
ready=0
for attempt in $(seq 1 40); do
  if docker exec "$name" pg_isready -U postgres -d collector_fixture >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "$ready" != 1 ]; then echo 'Fixture PostgreSQL did not start' >&2; exit 1; fi
{
  printf '%s\n' 'CREATE EXTENSION pg_stat_statements;' 'SELECT 1;' 'CREATE TEMP TABLE actual_metrics AS ('
  sed 's/;[[:space:]]*$//' "$work/query.sql"
  cat <<'SQL'
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM actual_metrics GROUP BY datname HAVING COUNT(*) > 1) THEN
    RAISE EXCEPTION 'duplicate datname labels';
  END IF;
END $$;
CREATE TEMP VIEW pg_stat_statements AS
 SELECT oid AS dbid, 10::bigint AS calls, 100.0::double precision AS total_exec_time FROM pg_database WHERE datname = current_database()
 UNION ALL SELECT oid, 2, 60.0 FROM pg_database WHERE datname = current_database()
 UNION ALL SELECT oid, 0, 0.0 FROM pg_database WHERE datname = 'postgres';
CREATE TEMP TABLE fixture_metrics AS (
SQL
  sed 's/;[[:space:]]*$//' "$work/query.sql"
  cat <<'SQL'
);
DO $$ DECLARE result record; BEGIN
 SELECT * INTO STRICT result FROM fixture_metrics WHERE datname = current_database();
 IF result.calls <> 12 OR result.total_time <> 160 OR ABS(result.mean_time - 160.0/12) > 0.00001 THEN
   RAISE EXCEPTION 'invalid summed counters or weighted mean';
 END IF;
 IF (SELECT COUNT(*) FROM fixture_metrics) <> 2 THEN RAISE EXCEPTION 'database groups lost'; END IF;
 IF (SELECT mean_time FROM fixture_metrics WHERE datname = 'postgres') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'zero-call mean must be zero'; END IF;
END $$;
SQL
} | docker exec -i "$name" psql -U postgres -d collector_fixture -v ON_ERROR_STOP=1 >/dev/null
docker exec "$name" psql -U postgres -d collector_fixture -v ON_ERROR_STOP=1 --csv -c "$(cat "$work/query.sql")" > "$work/metrics.csv"
python3 - "$root" "$work/metrics.csv" <<'PYTHON'
import csv, json, re, sys
from pathlib import Path
columns = csv.DictReader(open(sys.argv[2])).fieldnames
metrics = {'pg_stat_statements_' + column for column in columns if column != 'datname'}

def expressions(value):
    if isinstance(value, dict):
        if isinstance(value.get('expr'), str):
            yield value['expr']
        for item in value.values():
            yield from expressions(item)
    elif isinstance(value, list):
        for item in value:
            yield from expressions(item)

for dashboard in (Path(sys.argv[1])/'docker/grafana/dashboards').glob('*.json'):
    for expression in expressions(json.loads(dashboard.read_text())):
        unknown = set(re.findall(r'pg_stat_statements_[a-zA-Z0-9_]+', expression)) - metrics
        if unknown:
            raise SystemExit(f'{dashboard.name}: dashboard references absent metrics: {sorted(unknown)}')
PYTHON
printf 'PostgreSQL 16 metrics schema, unique labels and weighted mean passed.\n'
