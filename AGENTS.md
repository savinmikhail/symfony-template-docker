# Repository Guidelines

## Project Structure
- `app/`: Symfony backend.
- `docs/`: deployment notes, runbooks, and project documentation.
- `docker/` + `docker-compose.yml`: local and production-like infrastructure.
- `.github/`: CI/CD and deployment workflows.

## Working Style
- Use `task --list` for local development and quality tasks. Task delegates to the shared Make targets in `make/`, which CI can also call directly.
- Follow Conventional Commit style: `feat: ...`, `fix: ...`, `chore: ...`.
- Keep commits atomic and scoped to one logical change.
- Store secrets in `app/.env.local`; never commit real credentials.
- Run repository checks sequentially when they touch shared Docker services or the same database/container state.

## Production data access

- Pass production SQL on stdin through `make prod-query`; generated services must set their own `PROD_SSH_HOST` and `PROD_DEPLOY_PATH` defaults.
- The dedicated `llm` PostgreSQL role is local-socket-only, read-only, connection-limited, and has short query and lock timeouts.
- `prod-query` rejects backslashes so psql client-side meta-commands cannot reach production.

## Local Instructions
- Backend-specific guidance lives in [app/AGENTS.md](app/AGENTS.md).
- Backend module overviews live in `app/src/*/README.md`; start from [app/AGENTS.md](app/AGENTS.md) for the index.

## Product Workspace Synchronization

This repository is the reusable Symfony service baseline for the six product repositories under `/Users/mikhailsavin/projects`: `mock`, `platform`, `tech-tasks`, `interviews`, `mentoring_bi`, and `auth`.

- When a reusable infrastructure or developer-experience improvement is discovered while working in a product repository (for example CI/CD, Docker/Compose, Make targets, quality tooling, observability, or local setup), port the generic part into this template in the same task when practical.
- When changing a reusable baseline here, evaluate the six product repositories for rollout so new projects and active services do not drift.
- Keep the template generic: do not copy product-specific services, secrets, image names, ports, or deployment assumptions. Keep changes and commits scoped per repository.

## Production deployment

- Keep one supported production deployment path. Commit and push changes to deployment, provisioning and monitoring in the owning repository, then apply them through the existing release or provisioning workflow.
- Keep production reproducible on a replacement host using versioned configuration and documented inputs for secrets, inventory and data restoration. Use direct server access for read-only diagnostics. For an explicitly authorized incident workaround, reconcile the change into the canonical workflow and verify that it deploys from Git.
- Keep one owner for each setting. Docker Compose defines application services. Ansible provisions hosts and applies the canonical Compose files with inventory inputs. Extend the existing path with the smallest change needed and remove superseded configuration as part of its replacement.

## Production changes

Production access is read-only by default. A change to production state requires
a reviewed, merged PR deployed by the owning repository's standard release
process, or explicit user approval for the specific direct production action.
Use PR → review → merge → release, then verify the deployed revision and health.
Treat SSH, SQL writes, service restarts, runtime config edits, timers, and data
deletion as direct changes. A general request to implement a feature does not
authorize a direct production change.
