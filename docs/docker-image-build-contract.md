# Docker image build contract

This is the reusable contract for applying the PHP image pattern to a product repository. Keep repository-specific services, commands, extensions, labels, image names, and network topology in that repository.

## Dockerfile stages and pins

- Keep stable target names used by local Compose and CI (`dev`, `ci`, `build`, `prod`, plus any existing project targets).
- Pin each Dockerfile frontend, base image, and external `COPY --from` image as `version-tag@sha256:<multi-platform-index-digest>`. Verify that the digest is an image index and includes every supported platform (at least `linux/amd64` and `linux/arm64` where both are built).
- Update the version tag and digest together after reviewing the new image; do not keep a rolling tag beside an unrelated digest.
- Put required runtime libraries and extensions in a runtime stage. Put Composer, extension-install helpers, compilers, Git, and other build-only tools in dev/build stages. Do not copy Composer caches or development-only vendor trees into the final runtime target.
- Copy Composer manifests and lock files before application source, install dependencies in a named dependency stage, then copy source and run source-dependent autoload generation and framework cache warmup. Keep `.dockerignore` exclusions aligned with the CI target so local vendor/cache directories do not enter the build context while tests and required source remain available.
- Exclude repository-root local `.env` files from Docker context; re-include a product's tracked `app/.env` when Symfony needs it in the runtime image.
- Keep PHP and frontend dependencies on separate cache boundaries. Do not pin Debian packages mechanically; pin one only when a reproducibility or compatibility issue is evidenced and documented.

## Compose and pipeline behavior

- The `interviews` reference is for the multi-stage dependency/runtime design. Preserve each product's extensions, worker entrypoints, PHP-FPM settings, preload behavior, and runtime files when applying it.
- The `mock` reference is for sharing a dev PHP image/build anchor across PHP-FPM and workers. Reuse one image ref only when those services use the same build context, Dockerfile, target, build args, and runtime image; give services separate commands and environment as needed. Apply the same rule to production services only when their runtime artifact is identical.
- Preserve meaningful build args with the target that consumes them (for example, `HOST_UID`/`HOST_GID` for dev and `APP_VERSION` for the Nginx production build). Services sharing one image must also share the same effective args.
- Production releases ship Composer dependencies in the image. The template's `composer-install-prod` entrypoint verifies that `vendor/autoload.php` is present and reports a rebuild error if it is missing; runtime repair through Composer is intentionally not part of the immutable image flow.
- Preserve production and CI targets, image labels, registry names and publishing, Compose project networking, aliases, and service-specific production overrides. A template-level optimization must not flatten product-specific networking or release behavior.
- Prefer the repository Makefile as the entrypoint. In this template, `make docker-image-audit` delegates to `docker/audit-image-build.sh`.

## Measurement

Run the audit on the same Docker host, architecture, target, context, args, and Buildx configuration before and after a change:

```sh
make docker-image-audit DOCKER_AUDIT_TARGET=prod DOCKER_AUDIT_IMAGE=app-audit:local
make docker-image-audit DOCKER_AUDIT_DOCKERFILE=docker/nginx/Dockerfile DOCKER_AUDIT_TARGET=prod DOCKER_AUDIT_IMAGE=app-nginx-audit:local
```

The helper performs a BuildKit `--no-cache` build, a normal cache-seed build, and an identical normal build to measure warm-cache reuse. The seed matters because BuildKit does not use cache for the cold run and the first normal run may still rebuild layers. It records wall time, cached/build steps, image bytes, layer count, Docker history, and Dive wasted-space/efficiency using a pinned Dive container. Dive runs with networking disabled, reads a read-only Docker archive, and has no Docker socket. Builds are loaded to the local Docker engine; they do not push or deploy. The cold run disables BuildKit layer reuse, but does not clear already-pulled base images or external package/network caches. Keep the logs and Dive report for review.

BuildKit may report only incremental context transfer after it has seen the same context path. Use a fresh context path for total context transfer comparisons. Local image size is not a CI-time measurement. Claim CI acceleration only after comparing the corresponding CI runs under comparable runner/cache conditions. A single cold/warm pair is directional evidence, not a stable performance benchmark.
