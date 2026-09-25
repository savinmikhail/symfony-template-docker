#!/usr/bin/env bash
set -euo pipefail

dockerfile="${DOCKER_AUDIT_DOCKERFILE:-docker/php/Dockerfile}"
target="${DOCKER_AUDIT_TARGET:-prod}"
image="${DOCKER_AUDIT_IMAGE:-symfony-template-audit:local}"
context="${DOCKER_AUDIT_CONTEXT:-.}"
audit_dir="${DOCKER_AUDIT_DIR:-}"
dive_image="${DIVE_IMAGE:-docker.io/wagoodman/dive:v0.13.1@sha256:f1886e6c32c094fc41a623c1989f5cb3e48aa766da5f0be233f911fc1d85ce10}"
build_args=()

usage() {
  cat <<'EOF'
Usage: docker/audit-image-build.sh [--build-arg KEY=VALUE ...]

Environment:
  DOCKER_AUDIT_DOCKERFILE  Dockerfile path (default: docker/php/Dockerfile)
  DOCKER_AUDIT_TARGET      target to build (default: prod)
  DOCKER_AUDIT_IMAGE       local image tag (default: symfony-template-audit:local)
  DOCKER_AUDIT_CONTEXT     build context (default: .)
  DOCKER_AUDIT_DIR         output directory (default: a temporary directory)
  DIVE_IMAGE               analyzer image (default: Dive v0.13.1 pinned by digest)

Do not pass secrets as build arguments. Use BuildKit secret mounts instead.
EOF
}

while (($#)); do
  case "$1" in
    --build-arg)
      if (($# < 2)); then
        echo "--build-arg requires KEY=VALUE" >&2
        exit 2
      fi
      build_args+=(--build-arg "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$audit_dir" ]]; then
  audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/docker-image-audit.XXXXXX")"
else
  mkdir -p "$audit_dir"
fi
audit_dir="$(cd "$audit_dir" && pwd)"

archive_dir="$(mktemp -d "${TMPDIR:-/tmp}/docker-image-audit-archive.XXXXXX")"
image_archive="$archive_dir/image.tar"
cleanup() {
  rm -rf "$archive_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

monotonic_now() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(time.monotonic())'
  else
    date +%s
  fi
}

run_build() {
  local mode="$1"
  local log="$audit_dir/$mode-build.log"
  local start end elapsed cache_hits build_steps
  local -a build_cmd=(docker buildx build --progress=plain --load --file "$dockerfile" --target "$target")

  if [[ "$mode" == cold ]]; then
    build_cmd+=(--no-cache)
  fi
  build_cmd+=("${build_args[@]}" --tag "$image" "$context")

  start="$(monotonic_now)"
  if ! "${build_cmd[@]}" >"$log" 2>&1; then
    echo "$mode build failed; last build output follows:" >&2
    tail -n 80 "$log" >&2
    return 1
  fi
  end="$(monotonic_now)"
  elapsed="$(awk -v start="$start" -v end="$end" 'BEGIN { printf "%.2f", end - start }')"
  cache_hits="$(grep -c ' CACHED$' "$log" || true)"
  build_steps="$(grep -Ec '^#[0-9]+ \[' "$log" || true)"
  printf '%s build: %ss, cached steps: %s/%s, log: %s\n' "$mode" "$elapsed" "$cache_hits" "$build_steps" "$log"
}

if ! command -v docker >/dev/null 2>&1 || ! docker buildx version >/dev/null 2>&1; then
  echo "Docker Buildx is required." >&2
  exit 1
fi

printf 'Building local image %s (target %s, Dockerfile %s, context %s)\n' "$image" "$target" "$dockerfile" "$context"
printf 'Docker daemon platform: %s/%s\n' "$(docker info --format '{{.OSType}}')" "$(docker info --format '{{.Architecture}}')"
printf 'Audit output: %s\n' "$audit_dir"
run_build cold
run_build seed
run_build warm

image_stats="$(docker image inspect --format '{{.Size}} {{len .RootFS.Layers}}' "$image")"
image_bytes="${image_stats%% *}"
layer_count="${image_stats##* }"
image_mib="$(awk -v bytes="$image_bytes" 'BEGIN { printf "%.1f", bytes / 1048576 }')"
printf 'Image: %s, %s MiB, %s layers\n' "$image" "$image_mib" "$layer_count"

docker history --no-trunc --format '{{.Size}}{{"\t"}}{{.CreatedBy}}' "$image" >"$audit_dir/image-history.txt"
printf 'Layer history: %s\n' "$audit_dir/image-history.txt"

docker image save --output "$image_archive" "$image"
dive_report="$audit_dir/dive.json"
if ! docker run --rm \
  --network none \
  --env CI=true \
  --volume "$image_archive:/image.tar:ro" \
  --volume "$audit_dir:/audit" \
  "$dive_image" \
  --source docker-archive \
  --json /audit/dive.json \
  /image.tar >"$audit_dir/dive.log" 2>&1; then
  echo "Dive failed to analyze $image; last output follows:" >&2
  tail -n 80 "$audit_dir/dive.log" >&2
  exit 1
fi
if command -v jq >/dev/null 2>&1; then
  jq -r '"Dive: size=" + ((.image.sizeBytes / 1048576 * 10 | round) / 10 | tostring) + " MiB, wasted=" + ((.image.inefficientBytes / 1048576 * 10 | round) / 10 | tostring) + " MiB, efficiency=" + ((.image.efficiencyScore * 100 * 100 | round) / 100 | tostring) + "%"' "$dive_report"
else
  printf 'Dive report: %s\n' "$dive_report"
fi

printf 'Image retained locally for inspection: %s\n' "$image"
