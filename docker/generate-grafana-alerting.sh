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

is_digits() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

case "${APP_GRAFANA_TELEGRAM_CHAT_ID}" in
  -*) is_digits "${APP_GRAFANA_TELEGRAM_CHAT_ID#-}" ;;
  @*)
    channel_name=${APP_GRAFANA_TELEGRAM_CHAT_ID#@}
    case "${channel_name}" in
      ''|*[!A-Za-z0-9_]*) false ;;
      *) true ;;
    esac
    ;;
  *) is_digits "${APP_GRAFANA_TELEGRAM_CHAT_ID}" ;;
esac || {
  echo "APP_GRAFANA_TELEGRAM_CHAT_ID must be a numeric chat ID or @channel username" >&2
  exit 1
}

chat_id=$(yaml_escape "${APP_GRAFANA_TELEGRAM_CHAT_ID}")


cat > "${output_path}" <<EOF
apiVersion: 1

contactPoints:
  - orgId: 1
    name: symfony-template-docker-telegram
    receivers:
      - uid: symfony_template_docker_telegram
        type: telegram
        disableResolveMessage: false
        settings:
          bottoken: "\$APP_GRAFANA_TELEGRAM_BOT_TOKEN"
          chatid: "${chat_id}"
          parse_mode: HTML
          message: |
            {{ template "symfony-template-docker.message" . }}

  - orgId: 1
    name: symfony-template-docker-telegram-events
    receivers:
      - uid: symfony_template_docker_telegram_events
        type: telegram
        disableResolveMessage: true
        settings:
          bottoken: "\$APP_GRAFANA_TELEGRAM_BOT_TOKEN"
          chatid: "${chat_id}"
          parse_mode: HTML
          message: |
            {{ template "symfony-template-docker.message" . }}

policies:
  - orgId: 1
    receiver: symfony-template-docker-telegram
    group_by:
      - grafana_folder
      - alertname
      - service
      - integration
      - method
      - status_code
      - failure_kind
      - channel
      - error_kind
      - error_severity
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes:
      # Log event windows expiring do not prove that their causes were fixed.
      - receiver: symfony-template-docker-telegram-events
        object_matchers:
          - ['notification_class', '=~', 'application_error|outbound_http|http_5xx|log_event']
        continue: false
      - receiver: symfony-template-docker-telegram
        object_matchers:
          - ['severity', '=~', 'critical|warning']
        continue: false
EOF

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cat >> "${output_path}" <<'EOF'

templates:
  - orgId: 1
    name: symfony-template-docker.message
    template: |
EOF
sed 's/^/      /' "$script_dir/grafana/notification-message.tmpl" >> "${output_path}"
chmod 644 "${output_path}"
