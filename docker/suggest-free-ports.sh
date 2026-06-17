#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${repo_root}"

fail_if_busy=0
if [[ ${1:-} == "--fail-if-busy" ]]; then
  fail_if_busy=1
fi

declare -A defaults=()
declare -A values=()
declare -A occupied=()
declare -A reserved=()
declare -A own_published_ports=()

register_default() {
  local var_name=$1
  local port=$2

  [[ ${var_name} == APP_*_PORT ]] || return 0
  [[ ${port} =~ ^[0-9]+$ ]] || return 0

  if [[ -z ${defaults[$var_name]+x} ]]; then
    defaults[$var_name]=$port
  fi
}

collect_defaults_from_compose() {
  local file=$1
  [[ -f ${file} ]] || return 0

  while IFS=: read -r var_name port; do
    register_default "$var_name" "$port"
  done < <(
    perl -ne 'while(/\$\{(APP_[A-Z0-9_]+_PORT):-([0-9]+)\}/g){print "$1:$2\n"}' "$file"
  )
}

load_values_from_env_file() {
  local file=$1
  [[ -f ${file} ]] || return 0

  while IFS='=' read -r raw_name raw_value; do
    local name value
    name=$(printf '%s' "$raw_name" | sed 's/[[:space:]]//g')
    [[ ${name} == APP_*_PORT ]] || continue

    value=$(printf '%s' "${raw_value:-}" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    value=${value%\"}
    value=${value#\"}
    value=${value%\'}
    value=${value#\'}
    [[ ${value} =~ ^[0-9]+$ ]] || continue

    values[$name]=$value
  done < <(grep -E '^[[:space:]]*APP_[A-Z0-9_]+_PORT=' "$file" || true)
}

collect_own_published_ports() {
  local row published_port

  while IFS= read -r row; do
    [[ -n ${row} ]] || continue

    published_port=$(printf '%s\n' "${row}" | php -r '
$row = trim(stream_get_contents(STDIN));
if ($row === "") {
    exit(0);
}
$decoded = json_decode($row, true);
if (!is_array($decoded)) {
    exit(0);
}
$publishers = $decoded["Publishers"] ?? [];
if (!is_array($publishers)) {
    exit(0);
}
foreach ($publishers as $publisher) {
    if (!is_array($publisher)) {
        continue;
    }
    $port = $publisher["PublishedPort"] ?? null;
    if (is_int($port) || (is_string($port) && ctype_digit($port))) {
        echo $port, PHP_EOL;
    }
}
')

    while IFS= read -r port; do
      [[ ${port} =~ ^[0-9]+$ ]] || continue
      own_published_ports[$port]=1
    done <<< "${published_port}"
  done < <(
    docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml ps --format json 2>/dev/null || true
  )
}

is_port_busy() {
  local port=$1

  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  echo "Need ss or lsof to inspect host ports." >&2
  exit 1
}

find_free_port() {
  local start_port=$1
  local candidate=$((start_port + 1))

  while :; do
    if [[ -z ${reserved[$candidate]+x} ]] && ! is_port_busy "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate=$((candidate + 1))
  done
}

collect_defaults_from_compose docker-compose.yml
collect_defaults_from_compose docker-compose.prod.yml
collect_defaults_from_compose docker-compose.monitoring.yml

load_values_from_env_file .env
load_values_from_env_file .env.local
collect_own_published_ports

for var_name in "${!defaults[@]}"; do
  if [[ -z ${values[$var_name]+x} ]]; then
    values[$var_name]=${defaults[$var_name]}
  fi
done

if [[ ${#values[@]} -eq 0 ]]; then
  echo "No APP_*_PORT variables found."
  exit 0
fi

while IFS= read -r var_name; do
  reserved[${values[$var_name]}]=1
done < <(printf '%s\n' "${!values[@]}" | sort)

for var_name in "${!values[@]}"; do
  current_port=${values[$var_name]}
  if is_port_busy "$current_port"; then
    if [[ -n ${own_published_ports[$current_port]+x} ]]; then
      continue
    fi
    occupied[$var_name]=$current_port
  fi
done

if [[ ${#occupied[@]} -eq 0 ]]; then
  echo "All APP_*_PORT values are free."
  exit 0
fi

echo "# Busy ports detected. Suggested overrides for .env.local:"
while IFS= read -r var_name; do
  current_port=${occupied[$var_name]}
  suggested_port=$(find_free_port "$current_port")
  reserved[$suggested_port]=1
  printf '%s=%s\n' "$var_name" "$suggested_port"
done < <(printf '%s\n' "${!occupied[@]}" | sort)

if [[ $fail_if_busy -eq 1 ]]; then
  exit 1
fi
