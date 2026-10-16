#!/usr/bin/env bash
set -euo pipefail
ref="refs/tags/${1:?Tag required}"
scope=full
if [[ "$(git cat-file -t "$ref")" == tag ]]; then
  fields="$(git for-each-ref --format='%(contents)' "$ref" | git interpret-trailers --parse | sed -n 's/^Deploy-Scope: //p')"
  if [[ -n "$fields" ]]; then scope="$fields"; fi
fi
case "$scope" in full|web-only|media-only|creator-playback-only|frontend-only) printf '%s\n' "$scope" ;; *) echo "Invalid or duplicate Deploy-Scope in tag" >&2; exit 1 ;; esac
