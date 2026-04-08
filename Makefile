SHELL := /bin/sh

PROD_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.prod.yml
MONITORING_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.monitoring.yml
MONITORING_SERVICES := php nginx db redis rabbitmq postgres-exporter redis-exporter rabbitmq-exporter php-fpm-exporter prometheus grafana loki
KICS_IMAGE ?= checkmarx/kics@sha256:3e5a268eb8adda2e5a483c9359ddfc4cd520ab856a7076dc0b1d8784a37e2602
KICS_EXCLUDE_PATHS ?= /path/app/vendor,/path/frontend/node_modules,/path/app/tools
KICS_HIGH_EXCLUDE_SEVERITIES ?= info,trace,low,medium
KICS_FULL_EXCLUDE_SEVERITIES ?= info,trace
SECRET_LENGTH ?= 32
APP_SECRET_LENGTH ?= 64
GEN_SECRETS_SCRIPT := ./docker/generate-secrets.sh
GEN_SECRETS_VARS := POSTGRES_PASSWORD RABBITMQ_DEFAULT_PASS APP_GRAFANA_ADMIN_PASSWORD APP_SECRET

HOST_UID ?= $(shell id -u)
HOST_GID ?= $(shell id -g)
export HOST_UID
export HOST_GID

# Загружаем переменные из .env и .env.local (локальный имеет приоритет)
ifneq (,$(wildcard .env))
include .env
export
endif

ifneq (,$(wildcard .env.local))
include .env.local
export
endif

.PHONY: up up-monitoring up-prod check-loki-driver check-monitoring-env check-prod-env wait-prod composer-install composer-install-prod php-rebuild php phpstan phpat dep-analyse cs-fix rector gen-secrets kics kics-high kics-full k6 worker dmm dmm-prod prod-cache-reset

up:
	docker compose up -d --build
	$(MAKE) composer-install
	$(MAKE) dmm
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"

up-monitoring:
	$(MAKE) check-loki-driver
	$(MAKE) check-monitoring-env
	$(MONITORING_COMPOSE) up -d $(MONITORING_SERVICES)

up-prod:
	$(MAKE) check-prod-env
	$(PROD_COMPOSE) up -d --build
	$(MAKE) wait-prod
	$(MAKE) composer-install-prod
	$(MAKE) prod-cache-reset
	$(MAKE) dmm-prod
	@echo
	@echo "Production application is available at: http://localhost:$(APP_HTTP_PORT)/"

check-loki-driver:
	@docker plugin inspect loki >/dev/null 2>&1 || { \
		echo "Docker Loki logging driver is not installed." >&2; \
		echo "Install it first, for example: docker plugin install grafana/loki-docker-driver:3.7.0-<amd64|arm64> --alias loki --grant-all-permissions" >&2; \
		exit 1; \
	}

check-prod-env:
	@sh ./docker/verify-prod-env.sh prod

check-monitoring-env:
	@sh ./docker/verify-prod-env.sh monitoring

wait-prod:
	until $(PROD_COMPOSE) exec -T php php -v >/dev/null 2>&1; do sleep 2; done

composer-install:
	docker compose exec -T -u $(HOST_UID):$(HOST_GID) php sh -lc 'mkdir -p vendor && composer install --no-interaction --prefer-dist'

composer-install-prod:
	$(PROD_COMPOSE) exec -T php sh -lc 'if [ ! -f vendor/autoload.php ]; then composer install --no-dev --prefer-dist --no-interaction --classmap-authoritative; fi'

php-rebuild:
	docker compose up -d --no-deps --build php
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"

php:
	docker compose exec php bash

phpstan:
	docker compose exec php php tools/phpstan/vendor/bin/phpstan analyse -c phpstan.neon.dist

phpat:
	docker compose exec php php tools/phpat/vendor/bin/phpstan analyse -c phpat.neon.dist src tests/Architecture

dep-analyse:
	docker compose exec php php tools/composer-dependency-analyser/vendor/bin/composer-dependency-analyser --composer-json composer.json --config composer-dependency-analyser.php

cs-fix:
	docker compose exec php php tools/php-cs-fixer/vendor/bin/php-cs-fixer fix

rector:
	docker compose exec php php tools/rector/vendor/bin/rector process

gen-secrets:
	@SECRET_LENGTH=$(SECRET_LENGTH) APP_SECRET_LENGTH=$(APP_SECRET_LENGTH) $(GEN_SECRETS_SCRIPT) $(GEN_SECRETS_VARS)

kics:
	$(MAKE) kics-high

kics-high:
	docker run --rm -v "$$PWD:/path" $(KICS_IMAGE) scan -p /path --exclude-paths $(KICS_EXCLUDE_PATHS) --exclude-severities $(KICS_HIGH_EXCLUDE_SEVERITIES) --no-progress

kics-full:
	docker run --rm -v "$$PWD:/path" $(KICS_IMAGE) scan -p /path --exclude-paths $(KICS_EXCLUDE_PATHS) --exclude-severities $(KICS_FULL_EXCLUDE_SEVERITIES) --no-progress

k6:
	docker compose run --rm k6

worker:
	docker compose exec php php bin/console messenger:consume async -vv

dmm:
	docker compose exec php php bin/console doctrine:migration:migrate -n

dmm-prod:
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug doctrine:migration:migrate -n

prod-cache-reset:
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug cache:clear --no-warmup
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug cache:warmup
