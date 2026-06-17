#!/bin/sh
set -eu

output_path=${1:-tmp/grafana/provisioning/alerting/contactpoints.yml}

is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_env() {
  var_name=$1
  eval "value=\${$var_name-}"

  if [ -z "${value}" ]; then
    echo "Missing required env: ${var_name}" >&2
    exit 1
  fi
}

yaml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

mkdir -p "$(dirname "${output_path}")"

if ! is_true "${APP_GRAFANA_TELEGRAM_ENABLED:-0}"; then
  cat > "${output_path}" <<'EOF'
apiVersion: 1
EOF
  chmod 644 "${output_path}"
  exit 0
fi

require_env APP_GRAFANA_TELEGRAM_BOT_TOKEN
require_env APP_GRAFANA_TELEGRAM_CHAT_ID

bot_token=$(yaml_escape "${APP_GRAFANA_TELEGRAM_BOT_TOKEN}")
chat_id=$(yaml_escape "${APP_GRAFANA_TELEGRAM_CHAT_ID}")

cat > "${output_path}" <<EOF
apiVersion: 1

contactPoints:
  - orgId: 1
    name: service-telegram
    receivers:
      - uid: service_telegram
        type: telegram
        disableResolveMessage: false
        settings:
          bottoken: "${bot_token}"
          chatid: "${chat_id}"
          message: |
            {{ template "default.message" . }}

policies:
  - orgId: 1
    receiver: service-telegram
    group_by:
      - grafana_folder
      - alertname
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes:
      - receiver: service-telegram
        object_matchers:
          - ['severity', '=~', 'critical|warning']
        continue: false
EOF

chmod 644 "${output_path}"
