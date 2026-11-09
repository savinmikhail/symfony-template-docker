#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: audit-image-security.sh IMAGE DOCKERFILE [TARGET]}"
dockerfile="${2:?Dockerfile required}"
target="${3:-}"
platform="${DOCKER_SCOUT_PLATFORM:-linux/amd64}"
context="${DOCKER_SCOUT_CONTEXT:-.}"
# Fail before building when the local Scout plugin is missing.
docker scout version >/dev/null
args=(buildx build --load --platform "$platform" --file "$dockerfile" --tag "$image")
if [[ -n "${DOCKER_SCOUT_BUILDER:-}" ]]; then args+=(--builder "$DOCKER_SCOUT_BUILDER"); fi
if [[ -n "$target" ]]; then args+=(--target "$target"); fi
if [[ -n "${DOCKER_SCOUT_BUILD_CACHE_FROM:-}" ]]; then
  args+=(--cache-from "type=registry,ref=$DOCKER_SCOUT_BUILD_CACHE_FROM")
fi
docker "${args[@]}" "$context"
# Only build layers are reusable. Advisory data and indexing are fresh every run.
scout_cache="$(mktemp -d)"
trap 'rm -rf "$scout_cache"' EXIT
vex_args=()
if [[ "$dockerfile" == docker/nginx/Dockerfile ]]; then
  vex_args=(--only-vex-affected --vex-author 'Symfony Docker template maintainers'
    --vex-location "$(dirname "$0")/vex/alpine-3.24-musl.vex.json")
fi
DOCKER_SCOUT_NO_CACHE=true DOCKER_SCOUT_CACHE_DIR="$scout_cache" \
  docker scout cves --only-severity critical,high --only-fixed --exit-code "${vex_args[@]}" "local://$image"
