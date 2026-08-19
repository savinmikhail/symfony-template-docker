# Symfony 7.4 Docker Template

This repository is a **template** for Symfony 7.4 services with a small Vue SPA running in Docker:

- PHP‑FPM 8.4 (Alpine) with Symfony 7.4
- Vue 3 + Vite frontend for a quick SPA start
- Nginx as HTTP entrypoint and production static asset server
- PostgreSQL 16
- Redis
- RabbitMQ
- Doctrine ORM + migrations
- Symfony Messenger (Doctrine transports + failure transport)
- Observability stack: Prometheus, Grafana, Loki, Docker Loki logging driver, exporters
- k6 for HTTP load testing

The goal is to provide a **production‑like environment** for local development and experiments with metrics, logging and messaging.

---

## Project structure

- `app/` – Symfony application (Symfony 7.4 skeleton)
  - `src/`
    - `Entity/Product.php` – simple `Product` entity
    - `Repository/ProductRepository.php`
    - `Controller/ProductController.php` – sample API endpoints
  - `config/` – Symfony configuration (Doctrine, Messenger, Framework, Monolog, etc.)
  - `migrations/` – Doctrine migrations (organized by year & month)
  - `bin/` – console tools (`bin/console`, `bin/phpunit`)
  - `tools/` – isolated Composer tools (via `bamarni/composer-bin-plugin`)
    - `rector`, `php-cs-fixer`, `phpstan`, `phpat`, `composer-dependency-analyser`
- `frontend/` – Vue 3 + Vite SPA
  - `src/App.vue` – sample product catalog UI
  - `src/api.js` – minimal fetch wrapper for `/products`
  - `vite.config.js` – dev proxy to nginx for backend routes
- `docker/`
  - `php/` – PHP‑FPM Dockerfile and configs (`php.ini`, `php-fpm.conf`, `www.conf`, `xdebug.ini`)
  - `nginx/` – Nginx config + vhost
  - `postgres/` – tuned `postgresql.conf`, queries for exporter, `init.sql` (pg_stat_statements)
  - `prometheus/` – Prometheus configuration (scraping app exporters)
  - `grafana/` – provisioned datasources and dashboards (HTTP, Redis, RabbitMQ)
  - `loki/` – Loki configuration
  - `k6/load.js` – k6 load script for `/products` API
- `docker-compose.yml` – core application services
- `docker-compose.monitoring.yml` – optional observability stack
- `docker-compose.prod.yml` – production overrides for immutable runtime containers
- `Makefile` – helper commands for running the stack and tools
- `docs/deploy.md` – tag-based deployment and rollback workflow
- `.env` – root env vars (ports, resource sizes, etc.)
- `app/.env` – Symfony app env (DB & Messenger DSNs)

---

## Docker stack

Core services are defined in `docker-compose.yml`. Optional observability services live in `docker-compose.monitoring.yml` and can be started with:

```bash
make up-monitoring
```

or:

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

Override `APP_GRAFANA_ADMIN_PASSWORD` in `.env.local` before `make up-monitoring`, otherwise the guard will refuse to start Grafana with the committed placeholder.
Monitoring and admin ports are bound to `127.0.0.1`; if you need browser access from outside the host, publish them through a host-level reverse proxy instead of exposing raw ports directly.
`make up-monitoring` also expects the Docker Loki logging driver plugin to be installed on the host:
`docker plugin install grafana/loki-docker-driver:3.7.0-<amd64|arm64> --alias loki --grant-all-permissions`
Root `.env` now contains only infra-level variables; `DATABASE_URL` and `MESSENGER_TRANSPORT_DSN` are assembled inside [app/.env](/home/mikhail/projects/symfony-template-docker/app/.env) from the container env passed into `php`.

Defined in the core stack:

- `frontend` – Node 22 + Vite dev server
  - Mounts `./frontend` as project root
  - Exposed as `APP_FRONTEND_PORT` (default `5173`) on the host
  - Proxies `/products` to nginx inside Docker, so the SPA can call the Symfony API without CORS setup
  - Disabled in `docker-compose.prod.yml`; production frontend assets are built into the nginx image instead
- `php` – PHP 8.4 FPM (Alpine)
  - Built from `docker/php/Dockerfile`
  - Uses `install-php-extensions` (intl, opcache, pdo_pgsql, zip, xdebug in dev)
  - Dev image remaps `www-data` to `HOST_UID/HOST_GID` from the host
  - Keeps bind-mounted files like `app/vendor` writable on the host
  - Runs as `www-data`, working dir `/var/www/app`
  - Mounts `./app` as project root
- `nginx` – Nginx 1.27 (Alpine)
  - Configured via `docker/nginx/nginx.conf` and `docker/nginx/conf.d/app.conf`
  - Listens on port `8080` in the container
  - Exposed as `APP_HTTP_PORT` (default `8080`) on the host
  - In production, its image builds `frontend/dist` and serves the SPA directly
  - Access log in JSON to stdout (used by Loki)
- `db` – PostgreSQL 16 (Alpine)
  - Data volume: `db-data`
  - Tuned with `docker/postgres/postgresql.conf`
  - `pg_stat_statements` enabled via `init.sql`
  - Healthcheck via `pg_isready`
  - Published only on `127.0.0.1:${APP_DB_PORT}` in `docker-compose.yml`; `docker-compose.prod.yml` resets `db.ports`
- `redis` – Redis 7 (Alpine)
  - `maxmemory` taken from `APP_REDIS_MEMORY_LIMIT`
- `rabbitmq` – RabbitMQ 3 management
  - Credentials come from env; committed `.env` uses placeholder passwords that must be overridden in `.env.local` before production deploys
  - Ports:
    - AMQP: `127.0.0.1:${APP_RABBITMQ_PORT}` (default `5672`)
    - Management UI: `127.0.0.1:${APP_RABBITMQ_MGMT_PORT}` (default `15672`)
- Exporters & observability (`docker-compose.monitoring.yml`)
  - `postgres-exporter` – PostgreSQL metrics (Prometheus)
  - `redis-exporter` – Redis metrics (`oliver006/redis_exporter`)
  - `rabbitmq-exporter` – RabbitMQ metrics (`kbudde/rabbitmq-exporter`)
  - `prometheus` – metrics storage (`docker/prometheus/prometheus.yml`)
  - `grafana` – dashboards (Redis, RabbitMQ, HTTP, etc.)
  - `loki` – log storage
  - Docker Loki logging driver on the host ships container logs → Loki
- `k6` – Grafana k6 image for load testing

---

## Symfony application

### Database & Doctrine

- DB URL in `app/.env` is assembled from infra vars passed into the `php` container:

```dotenv
DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}?serverVersion=16&charset=utf8"
```

- Doctrine ORM mapping:
  - Attributes in `src/Entity`
  - Config in `app/config/packages/doctrine.yaml`
- Migrations:
  - Config: `app/config/packages/doctrine_migrations.yaml`
    - `organize_migrations: BY_YEAR_AND_MONTH`
  - Example migration: `app/migrations/Version20250101000000.php` (creates `product` table)

### Product entity & API

Entity: `App\Entity\Product`

Fields:
- `id` – integer, PK
- `name` – string
- `price` – decimal(10, 2) (stored as string)
- `createdAt` – `DateTimeImmutable`
- `updatedAt` – nullable `DateTimeImmutable`

Controller: `App\Controller\ProductController`

Routes:

- `GET /products`
  - Returns last 50 products ordered by `id DESC`.
  - Response example:
    ```json
    [
      {
        "id": 1,
        "name": "Product-ABC",
        "price": "19.99",
        "createdAt": "2025-01-01T12:00:00+00:00",
        "updatedAt": null
      }
    ]
    ```

- `POST /products`
  - Request body:
    ```json
    { "name": "Product name", "price": 9.99 }
    ```
  - On success: `201 Created` with created product.
  - On invalid payload: `400 Bad Request`.

## Frontend application

The `frontend/` directory is intentionally small so a new project can be started as a SPA without changing the Docker setup first.

Development:

```bash
make up
```

- Symfony/nginx API: `http://localhost:${APP_HTTP_PORT}`
- Vite frontend: `http://localhost:${APP_FRONTEND_PORT}`

Useful commands:

```bash
make frontend-install
make frontend-lint
make frontend-stylelint
make frontend-build
```

Production does not start the Vite dev server. `docker-compose.prod.yml` puts `frontend` behind the `dev` profile, while `docker/nginx/Dockerfile` runs `npm ci && npm run build` and copies `frontend/dist` into `/var/www/app/public`.

### Messenger

Package: `symfony/messenger`  
Config: `app/config/packages/messenger.yaml`

- Bus:
  - `messenger.bus.default`
  - Custom middleware stack:
    - `reject_redelivered_message_middleware`
    - `validation`
    - `doctrine_ping_connection`
    - `add_bus_name_stamp_middleware: ['messenger.bus.default']`
    - `dispatch_after_current_bus`
    - `send_message`
    - `failed_message_processing_middleware`
    - `handle_message`
    - `doctrine_close_connection`

- Failure transport:
  - `failure_transport: failed`
  - `failed` transport uses `doctrine://default?queue_name=failed`

- Transports (all customizable via env):
  - `async`, `notifications`, `search_index`, `modules_bell_async`, `scheduler_default`

- Env (`app/.env`):

```dotenv
MESSENGER_TRANSPORT_DSN=doctrine://default
MESSENGER_MODULES_BELL_ASYNC_TRANSPORT_DSN=doctrine://default
```

- Test override (`when@test`):
  - `async` and `notifications` use `test://` DSNs.

---

## Tooling

### Composer bin tools (in `app/tools`)

Isolated via `bamarni/composer-bin-plugin` with target directory `tools`:

- Rector:
  - `app/tools/rector/vendor/bin/rector`
  - Config: `app/rector.php`
- PHP CS Fixer:
  - `app/tools/php-cs-fixer/vendor/bin/php-cs-fixer`
  - Config: `app/.php-cs-fixer.dist.php`
- PHPStan:
  - `app/tools/phpstan/vendor/bin/phpstan`
  - Config: `app/phpstan.neon.dist`
- PHPat:
  - `app/tools/phpat/vendor/bin/phpstan`
  - Config: `app/phpat.neon.dist`
  - Rules: `app/tests/Architecture/ModuleBoundariesTest.php`
- Composer Dependency Analyser:
  - `app/tools/composer-dependency-analyser/vendor/bin/composer-dependency-analyser`
  - Config: `app/composer-dependency-analyser.php`

### PHPUnit

- Installed as dev dependency in `app/composer.json`.
- Config: `app/phpunit.dist.xml`.
- Run through `make test`; the target creates the test database, applies test migrations, and executes PHPUnit inside the PHP container.

---

## Production deploy

- Use `make up-prod` for local verification of the production stack.
- Use `make up-monitoring` only when the observability stack is actually needed.
- `make up-prod` fails fast if committed placeholder secrets were not overridden before a production start.
- `make up-prod` also fails fast on occupied `APP_*_PORT` values and prints ready-to-paste `.env.local` suggestions.
- `make suggest-free-ports` runs the same port scan on demand without aborting.
- `make gen-secrets` prints a ready-to-paste `.env.local` block with URL-safe secrets.
- `make kics` / `make kics-high` run the high-signal KICS infrastructure scan mirrored by the GitHub Actions workflow.
- `make kics-full` expands the scan to include medium findings such as missing cpu/ram limits.
- CI builds immutable production `php` and `nginx` images once in parallel and publishes them to GHCR under the commit SHA; regular deploys only pull and switch those images.
- The production `nginx` image contains the compiled SPA; the `frontend` dev service is not started by `make up-prod`.
- GitHub Actions deploys are tag-based, shown as the final job in the CI graph, and include automatic plus manual rollback to already published images.
- Details: [docs/deploy.md](/home/mikhail/projects/symfony-template-docker/docs/deploy.md)

---

## Observability

### Metrics (Prometheus)

Scrape configs in `docker/prometheus/prometheus.yml`:

- `prometheus` itself
- nginx exporter (`nginx-exporter:9113`)
- Symfony app metrics via `http://nginx:8080/metrics`
- PostgreSQL exporter (`postgres-exporter:9187`)
- PHP-FPM exporter (`php-fpm-exporter:9253`)
- backup metrics exporter (`backup-metrics-exporter:9100`) in the `prod` profile

### Dashboards (Grafana)

Provisioned via:

- Datasources:
  - `docker/grafana/provisioning/datasources/prometheus.yml`
  - `docker/grafana/provisioning/datasources/loki.yml`
- Dashboards:
  - Service overview – `docker/grafana/dashboards/service-overview.json`
  - Logs drilldown – `docker/grafana/dashboards/logs-drilldown.json`

Provisioned alert rules live in `docker/grafana/provisioning/alerting/service-alerts.yml`. Optional Telegram contact points are generated into `tmp/grafana/provisioning/alerting/contactpoints.generated.yml` before `make up-monitoring` / `make up-prod`.

Grafana runs on `127.0.0.1:${APP_GRAFANA_PORT}` (default `3000`). Override `APP_GRAFANA_ADMIN_USER` / `APP_GRAFANA_ADMIN_PASSWORD` in `.env.local` before exposing it anywhere beyond local development.

### Logs (Loki + Docker logging driver)

- Loki:
  - Config: `docker/loki/config.yml`
  - Exposed on `127.0.0.1:${APP_LOKI_PORT}` (default `3100`)
- Docker Loki logging driver:
  - Ships container logs directly from Docker to Loki
  - Requires the `loki` Docker plugin on the host
  - Provides Compose metadata such as `compose_project` / `compose_service`

PHP & Nginx are configured to write logs to `stdout`/`stderr`:

- Monolog:
  - Dev/test: `php://stdout`
  - Prod: `php://stderr` (JSON)
- Nginx:
  - JSON access logs to `stdout` with `request_time` and `upstream_response_time`

In Grafana → Explore → Loki you can query:

- `{compose_service="nginx"}` – HTTP logs
- `{compose_service="php"}` – Symfony/PHP logs

---

## Load testing with k6

Script: `docker/k6/load.js`

- Scenario:
  - `vus: 10`, `duration: 30s`
  - For each VU:
    1. `POST /products` (create product)
    2. `GET /products` (list products)
    3. `sleep(1)`

Base URL:

- Inside Docker network: `http://nginx:8080`
- Configurable via env var `BASE_URL`.

Service `k6` in `docker-compose.yml` uses the official `grafana/k6` image and mounts `docker/k6` as `/scripts`.

---

## Makefile commands

From the repository root:

- Start stack:
  - `make up`
  - Rebuilds PHP with your host UID/GID, installs Composer dependencies, applies migrations
  - App URL is printed (uses `APP_HTTP_PORT` from `.env`)
- Rebuild only PHP container:
  - `make php-rebuild`
- Shell inside PHP container:
  - `make php`

Static analysis / code style (run inside PHP container via Docker):

- `make phpstan` – runs PHPStan with `phpstan.neon.dist`
- `make phpat` – runs PHPat architecture rules with `phpat.neon.dist`
- `make dep-analyse` – runs Composer Dependency Analyser with `composer-dependency-analyser.php`
- `make cs-fix` – runs PHP CS Fixer with `.php-cs-fixer.dist.php`
- `make rector` – runs Rector with `rector.php`

Load testing:

- `make k6` – runs k6 with `docker/k6/load.js` against the running stack.

---

## Getting started

Prerequisites:

- Docker + Docker Compose
- Make (optional but recommended)

Steps:

1. Clone the repo:

   ```bash
   git clone <this-repo-url>
   cd symfony-template-docker
   ```

2. Start the stack:

   ```bash
   make up
   ```

   This rebuilds the PHP container with your host UID/GID, runs `composer install`, and applies database migrations.

3. If you need to re-run migrations manually:

   ```bash
   make php
   php bin/console doctrine:migrations:migrate
   ```

4. Test the API:

   ```bash
   curl http://localhost:8080/products
   curl -X POST http://localhost:8080/products \
     -H 'Content-Type: application/json' \
     -d '{"name":"Test","price":9.99}'
   ```

5. Run a basic load test:

   ```bash
   make k6
   ```

6. Explore metrics and logs:

   - Prometheus: `http://localhost:9090`
   - Grafana: `http://localhost:3000`
   - Loki via Grafana → Explore (logs from `nginx`, `php`, etc.)

---

## Notes & next steps

This template is intentionally minimal on **domain code** and heavy on **infrastructure**.  
You are expected to:

- Add your own entities, message handlers and routing.
- Switch Messenger transports to RabbitMQ (AMQP) if needed.
- Extend Grafana dashboards and alerting rules for your use‑cases.

Use this as a starting point for new Symfony API projects with Docker‑first, observability‑ready setup.
