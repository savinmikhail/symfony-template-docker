# Deploy

Production releases are tag-based and use immutable images from GitHub Container Registry. A regular deploy never rebuilds application code on the production host.

## Release flow

`make tag` creates and pushes the next patch tag. The tag starts the `CI` workflow:

1. the self-contained PHP CI image is built and published once;
2. backend quality and backend tests pull that exact image and run in parallel;
3. frontend checks run independently;
4. production `php` and `nginx` images build once in parallel and are published under the commit SHA;
5. `Deploy` is the final job in the same workflow graph and starts only after all required jobs succeed;
6. production pulls the exact SHA, runs backward-compatible migrations, switches the stateless containers, and performs an HTTP smoke check.

The reusable deploy workflow can also be started manually with a previously published tag. Manual dispatch is an operator override and does not rebuild images.

## Image names

The template defaults to:

- `ghcr.io/msavin-mentoring/symfony-template-docker-php:<commit-sha>`;
- `ghcr.io/msavin-mentoring/symfony-template-docker-nginx:<commit-sha>`.

When creating a repository from this template, replace the default values through `APP_PHP_IMAGE` and `APP_NGINX_IMAGE`, or update `docker-compose.prod.yml` to use the new repository name. `APP_IMAGE_TAG` is always the immutable commit SHA selected by the workflow.

## Automatic and manual rollback

Before switching containers, deploy reads the OCI revision label from the currently running PHP image. If deployment or the smoke check fails, it checks out that previous revision and starts the already published images again.

The manual `Rollback` workflow resolves the tag preceding `current_tag`, validates that it belongs to `main`, and switches to that tag's existing images. Neither rollback path rebuilds code. Database migrations are not reverted, so production migrations must be backward-compatible with the previous application version.

## Required GitHub configuration

The `production` GitHub Environment must contain:

- `DEPLOY_HOST`;
- `DEPLOY_PORT`;
- `DEPLOY_USER`;
- `DEPLOY_SSH_KEY`;
- `DEPLOY_PATH`;
- `DEPLOY_HOST_FINGERPRINT`.

`GITHUB_TOKEN` is supplied automatically and is used to publish and pull packages from the repository's GHCR namespace.

## Production host

Before the first release:

1. clone the repository to `DEPLOY_PATH`;
2. install Docker, Docker Compose, and the Docker Loki logging driver;
3. configure `.env.local` and `app/.env.local` with production secrets;
4. ensure the deploy user can run Docker and read the repository's GHCR packages;
5. start persistent infrastructure services and bootstrap the first labeled application images.

The regular `make deploy-prod` path only pulls `php` and `nginx`, runs migrations from the new PHP image, switches those services, and checks `/metrics`. PostgreSQL, Redis, RabbitMQ, and monitoring services are not rebuilt during an application release.

The first migration from locally built legacy images requires an operator bootstrap because those images do not contain the `org.opencontainers.image.revision` label used to identify the rollback target.

## Local production-like start

`make up-prod APP_IMAGE_TAG=<sha>` retains the full-stack production-like bootstrap path. It validates secrets and host ports, prepares monitoring, and may build locally. Automated releases use `make deploy-prod` instead.
