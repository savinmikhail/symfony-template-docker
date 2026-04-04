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
