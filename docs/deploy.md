# Deploy

## Manual Deploy

Production deploy is manual via GitHub Actions `workflow_dispatch`.

Workflow file:
- [deploy.yml](/home/mikhail/projects/symfony-template-docker/.github/workflows/deploy.yml)

The workflow:

1. connects to the server over SSH
2. switches repo to the requested git tag
3. runs `make up-prod`

Deploys are intentionally tag-based so rollback can target a previous release tag.

## Manual Rollback

Rollback is a separate manual GitHub Actions workflow.

Workflow file:
- [rollback.yml](/home/mikhail/projects/symfony-template-docker/.github/workflows/rollback.yml)

The rollback workflow:

1. connects to the server over SSH
2. fetches tags
3. finds the tag immediately before the provided `current_tag`
4. checks out that previous tag
5. runs `make up-prod`

## Required GitHub Secrets

- `DEPLOY_HOST`: production server hostname or IP
- `DEPLOY_PORT`: SSH port, usually `22`
- `DEPLOY_USER`: SSH user on the server
- `DEPLOY_SSH_KEY`: private key for deploy access
- `DEPLOY_PATH`: absolute path to the checked out repo on the server
- `DEPLOY_HOST_FINGERPRINT`: SSH host fingerprint for verification

## What `make up-prod` does

`make up-prod` now runs the production flow:

1. validates that production secrets were overridden outside the committed `.env`
2. `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build`
3. waits until PHP is ready
4. installs Composer dependencies only if `vendor/autoload.php` is missing
5. resets and warms up `var/cache/prod`
6. runs Doctrine migrations in `prod`

## First Production Setup

Before the first deploy:

1. ensure the repo is cloned on the server at `DEPLOY_PATH`
2. ensure Docker and Docker Compose are installed
3. ensure `.env` / `.env.local` or equivalent secrets are configured on the server
4. ensure the deploy user can run Docker commands

Production note:

- keep `POSTGRES_PASSWORD` and `RABBITMQ_DEFAULT_PASS` overridden outside the committed `.env`
- `make up-prod` fails fast if those vars still use committed placeholders/defaults
- `make up-monitoring` fails fast if `APP_GRAFANA_ADMIN_PASSWORD` still uses a committed placeholder/default
- `make up-monitoring` also requires the Docker Loki logging driver plugin (`loki`) to be installed on the host
- `docker-compose.prod.yml` resets `db.ports`, so PostgreSQL is not published on the host in production
- Redis, RabbitMQ and monitoring/admin ports are bound to `127.0.0.1` and should be published externally only through a host-level reverse proxy if needed
- app-level DSNs are assembled inside [app/.env](/home/mikhail/projects/symfony-template-docker/app/.env) from the container env, so they do not need a separate production override

## Notes

- Production must be started via `make up-prod`, not `make up`
- `make up` uses the `dev` PHP target with host UID/GID remapping
- `make up-prod` uses the `prod` targets for both `php` and `nginx`
- production compose removes bind mounts for application code so runtime matches the built image

## Rollback

Fast rollback is currently:

1. trigger the rollback workflow with the currently deployed tag
2. let the workflow resolve the previous tag and run `make up-prod`

Database rollback is not automated here. If a deploy includes destructive data changes, use a DB backup before rollout.
