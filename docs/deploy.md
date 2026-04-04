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

1. `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build`
2. waits until PHP is ready
3. installs Composer dependencies only if `vendor/autoload.php` is missing
4. resets and warms up `var/cache/prod`
5. runs Doctrine migrations in `prod`

## First Production Setup

Before the first deploy:

1. ensure the repo is cloned on the server at `DEPLOY_PATH`
2. ensure Docker and Docker Compose are installed
3. ensure `.env` / `.env.local` or equivalent secrets are configured on the server
4. ensure the deploy user can run Docker commands

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
