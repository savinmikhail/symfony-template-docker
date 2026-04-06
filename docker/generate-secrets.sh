#!/bin/sh
set -eu

secret_length=${SECRET_LENGTH:-32}
app_secret_length=${APP_SECRET_LENGTH:-64}

generate_secret() {
  length=$1
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}"
  printf '\n'
}

if [ "$#" -eq 0 ]; then
  echo "Usage: SECRET_LENGTH=32 APP_SECRET_LENGTH=64 $0 VAR_NAME [VAR_NAME ...]" >&2
  exit 1
fi

for var_name in "$@"; do
  case "${var_name}" in
    APP_SECRET)
      value=$(generate_secret "${app_secret_length}")
      ;;
    *)
      value=$(generate_secret "${secret_length}")
      ;;
  esac

  printf '%s=%s\n' "${var_name}" "${value}"
done
