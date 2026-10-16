#!/usr/bin/env bash
set -euo pipefail
repository="${1:?repository name required}"
runner="${2:?runner name required}"
trust="${3:?trust boundary required}"
case "$trust" in pr|trusted) ;; *) echo 'Invalid trust boundary' >&2; exit 2 ;; esac
# Preserve existing valid names and their persistent cache state.
legacy="ci-${repository}-${runner}-${trust}"
if [[ "$legacy" =~ ^[a-zA-Z][a-zA-Z0-9_.-]*$ ]]; then
    printf '%s\n' "$legacy"
    exit 0
fi
slug="$(printf '%s' "$repository" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9_.-' '-' | cut -c1-48)"
identity="$(printf '%s\0' "$repository" "$runner" "$trust" | sha256sum | cut -c1-16)"
printf 'ci-%s-%s-%s\n' "$slug" "$identity" "$trust"
