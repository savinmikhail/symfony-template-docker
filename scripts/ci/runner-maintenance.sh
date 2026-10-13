#!/usr/bin/env bash
# Host-wide maintenance: invoke only on the dedicated CI host, never a product host.
set -euo pipefail
if pgrep -f '[R]unner.Worker' >/dev/null; then
  echo 'Runner jobs active; maintenance skipped.'
  exit 0
fi
# Docker protects images referenced by containers. Retain three days for rollback/debugging.
docker image prune --all --force --filter 'until=72h'
# Old setup-buildx UUID builders are disposable. Named persistent ci-* builders are excluded.
cutoff=$(($(date +%s) - 172800))
while read -r container; do
  [[ -n "$container" ]] || continue
  name=$(docker inspect --format '{{.Name}}' "$container")
  [[ "$name" =~ ^/buildx_buildkit_builder-[0-9a-f]{8}- ]] || continue
  created=$(docker inspect --format '{{.Created}}' "$container")
  [[ $(date -d "$created" +%s) -lt $cutoff ]] || continue
  # Recheck before each removal in case a job started during image cleanup.
  if pgrep -f '[R]unner.Worker' >/dev/null; then exit 0; fi
  volume=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/buildkit"}}{{.Name}}{{end}}{{end}}' "$container")
  docker rm --force "$container"
  if [[ "$volume" == buildx_buildkit_builder-* ]]; then docker volume rm "$volume"; fi
done < <(docker ps --all --quiet --filter 'name=buildx_buildkit_builder-')
