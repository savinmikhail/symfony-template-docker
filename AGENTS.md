# Repository Guidelines

## Project Structure
- `app/`: Symfony backend.
- `docs/`: deployment notes, runbooks, and project documentation.
- `docker/` + `docker-compose.yml`: local and production-like infrastructure.
- `.github/`: CI/CD and deployment workflows.

## Working Style
- Use `Makefile` commands as the default entrypoint for build, test, and quality tasks.
- Follow Conventional Commit style: `feat: ...`, `fix: ...`, `chore: ...`.
- Keep commits atomic and scoped to one logical change.
- Store secrets in `app/.env.local`; never commit real credentials.
- Run repository checks sequentially when they touch shared Docker services or the same database/container state.

## Local Instructions
- Backend-specific guidance lives in [app/AGENTS.md](app/AGENTS.md).
- Backend module overviews live in `app/src/*/README.md`; start from [app/AGENTS.md](app/AGENTS.md) for the index.

## Product Workspace Synchronization

This repository is the reusable Symfony service baseline for the six product repositories under `/Users/mikhailsavin/projects`: `mock`, `platform`, `tech-tasks`, `interviews`, `mentoring_bi`, and `auth`.

- When a reusable infrastructure or developer-experience improvement is discovered while working in a product repository (for example CI/CD, Docker/Compose, Make targets, quality tooling, observability, or local setup), port the generic part into this template in the same task when practical.
- When changing a reusable baseline here, evaluate the six product repositories for rollout so new projects and active services do not drift.
- Keep the template generic: do not copy product-specific services, secrets, image names, ports, or deployment assumptions. Keep changes and commits scoped per repository.
