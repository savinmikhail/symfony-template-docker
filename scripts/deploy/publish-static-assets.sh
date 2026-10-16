#!/bin/sh
# Publish image assets while retaining old content-addressed resources.
set -eu
image=$1
source_path=$2
destination=$3
mkdir -p "$destination"
staging=$(mktemp -d)
container=$(docker create "$image")
trap 'docker rm "$container" >/dev/null; rm -rf "$staging"' EXIT HUP INT TERM
docker cp "$container:$source_path/." "$staging/"
for item in "$staging"/*; do
  [ -e "$item" ] || continue
  name=$(basename "$item")
  case "$name" in index.html|manifest.json) continue ;; esac
  cp -a "$item" "$destination/"
done
for entry in index.html manifest.json; do
  if [ -f "$staging/$entry" ]; then
    cp "$staging/$entry" "$destination/.$entry.next"
    mv "$destination/.$entry.next" "$destination/$entry"
  fi
done
