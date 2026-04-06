#!/bin/sh
set -eu

mode=${1:-prod}
failed=0

require_secret() {
  var_name=$1
  insecure_default=$2
  eval "value=\${$var_name-}"

  if [ -z "${value}" ]; then
    echo "Missing required production env: ${var_name}" >&2
    failed=1
    return
  fi

  case "${value}" in
    "${insecure_default}"|change-me-in-.env.local|local-db-password-change-me|local-rabbitmq-password-change-me)
      echo "Refusing production deploy: ${var_name} still uses a committed placeholder/default." >&2
      failed=1
      ;;
  esac
}

case "${mode}" in
  prod)
    require_secret POSTGRES_PASSWORD app
    require_secret RABBITMQ_DEFAULT_PASS app
    ;;
  monitoring)
    require_secret APP_GRAFANA_ADMIN_PASSWORD admin
    ;;
  *)
    echo "Unknown verification mode: ${mode}" >&2
    exit 1
    ;;
esac

if [ "${failed}" -ne 0 ]; then
  case "${mode}" in
    prod)
      echo "Override the production secrets in .env.local or the deployment environment and rerun make up-prod." >&2
      ;;
    monitoring)
      echo "Override the monitoring secrets in .env.local or the deployment environment and rerun make up-monitoring." >&2
      ;;
  esac
  exit 1
fi
