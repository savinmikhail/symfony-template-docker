# Backend Guidelines

## Structure
- `src/`: backend code.
- `tests/Feature/`: HTTP and flow tests.
- `migrations/`: Doctrine migrations.

## Module Docs
- Module README files live under `src/<Module>/README.md`.
- Before non-trivial work inside a module, read that module README if it exists.
- Current module docs: none yet.

## Development
- Prefer constructor DI and Symfony attributes over ad-hoc configuration where the codebase already does that.
- For request validation and mapping, prefer `MapRequestPayload` / `MapQueryString`.
- Prefer `make` targets over invoking tool binaries directly when an equivalent exists.
- Keep sample code simple, but when the application grows, introduce explicit module boundaries instead of extending a flat technical layout forever.

## Testing
- Framework: PHPUnit 12 via `app/phpunit.dist.xml`.
- For API or flow changes, add or update feature tests.
- Run Docker-backed tests sequentially; avoid parallel runs that share the same containers or database state.

## Quality
- Relevant commands are available through `make`, including:
- `make phpstan`
- `make cs-fix`
- `make rector`

## Architecture
- Prefer modulith architecture and package by feature for real projects built from this template.
- Once the app grows beyond the sample structure, prefer module folders under `src/` over spreading new code across broad technical top-level directories.
- Add short `README.md` files inside modules when introducing non-trivial behavior or boundaries.
- Keep domain logic out of controllers and other infrastructure entrypoints.
- Prefer rich models over anemic ones.

## Security and Messaging
- Store real secrets in `app/.env.local` or deployment-specific environment configuration.
- Messenger, Redis, and PostgreSQL are part of the default stack; keep local defaults safe and production overrides explicit.
