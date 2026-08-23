SHELL := /bin/sh

PROD_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.prod.yml
CI_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.ci.yml
PROD_MONITORING_COMPOSE := COMPOSE_PROFILES=prod docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.monitoring.yml
PROD_APP_SERVICES := php nginx
MONITORING_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.monitoring.yml
MONITORING_SERVICES := frontend php nginx db redis rabbitmq nginx-exporter postgres-exporter php-fpm-exporter prometheus grafana loki
GRAFANA_ALERTING_PROVISIONING_DIR := ./tmp/grafana/provisioning/alerting
GRAFANA_ALERTING_CONTACTPOINTS := $(GRAFANA_ALERTING_PROVISIONING_DIR)/contactpoints.generated.yml
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
APP_VERSION ?= $(shell git describe --tags --exact-match 2>/dev/null || echo dev)
export HOST_UID
export HOST_GID
export APP_VERSION

# Загружаем переменные из .env и .env.local (локальный имеет приоритет)
ifneq (,$(wildcard .env))
include .env
export
endif

ifneq (,$(wildcard .env.local))
include .env.local
export
endif

CURRENT_RELEASE_IMAGE_TAG := $(shell git describe --tags --exact-match >/dev/null 2>&1 && git rev-parse HEAD)
ifeq ($(strip $(APP_IMAGE_TAG)),)
APP_IMAGE_TAG := $(CURRENT_RELEASE_IMAGE_TAG)
endif
export APP_IMAGE_TAG

.PHONY: up up-monitoring grafana-alerting-provisioning suggest-free-ports check-free-ports up-prod check-loki-driver check-monitoring-env check-prod-env wait-prod reload-prometheus composer-install composer-install-prod frontend-install frontend-build frontend-lint frontend-stylelint frontend-ci-install frontend-ci-quality php-rebuild php phpstan phpat dep-analyse cs-fix cs-check rector rector-check composer-validate composer-audit prod-di-validate doctrine-schema-validate backend-quality ci-pull-php ci-up-php ci-up-tests ci-down test quality quality-dr gen-secrets tag kics kics-high kics-full k6 worker dmm dmm-prod prod-cache-reset backup-prod-now check-release-image-tag current-prod-image-sha pull-prod-images migrate-prod-image rollout-prod-postgres-backup switch-prod-app smoke-prod deploy-prod rollback-prod

up:
	docker compose up -d --build
	$(MAKE) composer-install
	$(MAKE) frontend-install
	$(MAKE) dmm
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"
	@echo "Frontend is available at: http://localhost:$(APP_FRONTEND_PORT)/"

suggest-free-ports:
	./docker/suggest-free-ports.sh

check-free-ports:
	./docker/suggest-free-ports.sh --fail-if-busy

up-monitoring:
	$(MAKE) check-loki-driver
	$(MAKE) check-monitoring-env
	$(MAKE) grafana-alerting-provisioning
	$(MONITORING_COMPOSE) up -d --wait --remove-orphans $(MONITORING_SERVICES)
	$(MAKE) reload-prometheus COMPOSE_CMD='$(MONITORING_COMPOSE)'

grafana-alerting-provisioning:
	@rm -rf $(GRAFANA_ALERTING_PROVISIONING_DIR)
	@mkdir -p $(GRAFANA_ALERTING_PROVISIONING_DIR)
	@cp docker/grafana/provisioning/alerting/*.yml $(GRAFANA_ALERTING_PROVISIONING_DIR)/
	@./docker/generate-grafana-alerting.sh $(GRAFANA_ALERTING_CONTACTPOINTS)

up-prod:
	$(MAKE) check-release-image-tag
	$(MAKE) check-free-ports
	$(MAKE) check-prod-env
	$(MAKE) check-loki-driver
	$(MAKE) check-monitoring-env
	$(MAKE) grafana-alerting-provisioning
	$(PROD_MONITORING_COMPOSE) up -d --wait --build --remove-orphans
	$(MAKE) reload-prometheus COMPOSE_CMD='$(PROD_MONITORING_COMPOSE)'
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

reload-prometheus:
	$(COMPOSE_CMD) kill --signal=HUP prometheus

composer-install:
	docker compose exec -T -u $(HOST_UID):$(HOST_GID) php sh -lc 'mkdir -p vendor && composer install --no-interaction --prefer-dist'

composer-install-prod:
	$(PROD_COMPOSE) exec -T php sh -lc 'if [ ! -f vendor/autoload.php ]; then composer install --no-dev --prefer-dist --no-interaction --classmap-authoritative; fi'

frontend-install:
	docker compose exec -T frontend npm install

frontend-build:
	docker compose exec -T frontend npm run build

frontend-lint:
	docker compose exec -T frontend npm run lint

frontend-stylelint:
	docker compose exec -T frontend npm run stylelint

frontend-ci-install:
	cd frontend && npm ci

frontend-ci-quality:
	cd frontend && npm audit --audit-level=high
	cd frontend && npm run lint
	cd frontend && npm run stylelint
	cd frontend && npm run build

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

cs-check:
	docker compose exec -T php php tools/php-cs-fixer/vendor/bin/php-cs-fixer fix --dry-run --diff

rector:
	docker compose exec php php tools/rector/vendor/bin/rector process

rector-check:
	docker compose exec -T php php tools/rector/vendor/bin/rector process --dry-run

composer-validate:
	docker compose exec -T -e COMPOSER_HOME=/tmp/composer php composer validate --strict --no-check-publish

composer-audit:
	docker compose exec -T -e COMPOSER_HOME=/tmp/composer php composer audit

prod-di-validate:
	docker compose exec -T -e APP_ENV=prod -e APP_DEBUG=0 php php bin/console lint:container --env=prod --no-debug

doctrine-schema-validate:
	docker compose exec -T -e APP_ENV=test -e APP_DEBUG=1 php php bin/console doctrine:database:create --env=test --if-not-exists --no-interaction
	docker compose exec -T -e APP_ENV=test -e APP_DEBUG=1 php php bin/console doctrine:migrations:migrate --env=test --no-interaction
	docker compose exec -T -e APP_ENV=test -e APP_DEBUG=1 php php bin/console doctrine:schema:validate --env=test --skip-sync --no-interaction
	docker compose exec -T -e APP_ENV=test -e APP_DEBUG=1 php php bin/console doctrine:migrations:up-to-date --env=test --no-interaction

backend-quality:
	$(MAKE) composer-validate
	$(MAKE) composer-audit
	$(MAKE) phpstan
	$(MAKE) phpat
	$(MAKE) dep-analyse
	$(MAKE) cs-check
	$(MAKE) rector-check
	$(MAKE) prod-di-validate

ci-pull-php:
	$(CI_COMPOSE) pull php

ci-up-php:
	$(CI_COMPOSE) up -d --no-build --no-deps php

ci-up-tests:
	$(CI_COMPOSE) up -d --no-build db redis rabbitmq php

ci-down:
	$(CI_COMPOSE) down -v

test:
	docker compose exec -T php php bin/console --env=test doctrine:database:create --if-not-exists --no-interaction
	docker compose exec -T php php bin/console --env=test doctrine:migrations:migrate -n
	$(MAKE) doctrine-schema-validate
	docker compose exec -T php php bin/phpunit

quality:
	$(MAKE) frontend-ci-install
	$(MAKE) frontend-ci-quality
	$(MAKE) backend-quality
	$(MAKE) test

quality-dr: quality

gen-secrets:
	@SECRET_LENGTH=$(SECRET_LENGTH) APP_SECRET_LENGTH=$(APP_SECRET_LENGTH) $(GEN_SECRETS_SCRIPT) $(GEN_SECRETS_VARS)

tag:
	@set -eu; \
	CURRENT_BRANCH=$$(git branch --show-current); \
	if [ "$$CURRENT_BRANCH" != "main" ]; then \
		echo "Releases must be created from main; current branch is $$CURRENT_BRANCH." >&2; \
		exit 1; \
	fi; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "Release tags only include committed changes. Commit or stash the dirty working tree first." >&2; \
		exit 1; \
	fi
	$(MAKE) quality
	@set -eu; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "Quality changed the working tree. Review and commit those changes before tagging." >&2; \
		exit 1; \
	fi; \
	git push origin main; \
	git fetch origin --tags --prune; \
	LATEST_TAG=$$(git tag --list 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | head -n 1); \
	if [ -z "$$LATEST_TAG" ]; then \
		LATEST_TAG="v0.0.0"; \
	fi; \
	VERSION=$${LATEST_TAG#v}; \
	MAJOR=$$(printf '%s' "$$VERSION" | cut -d. -f1); \
	MINOR=$$(printf '%s' "$$VERSION" | cut -d. -f2); \
	PATCH=$$(printf '%s' "$$VERSION" | cut -d. -f3); \
	NEXT_TAG="v$${MAJOR}.$${MINOR}.$$((PATCH + 1))"; \
	if git rev-parse -q --verify "refs/tags/$$NEXT_TAG" >/dev/null; then \
		echo "Tag $$NEXT_TAG already exists." >&2; \
		exit 1; \
	fi; \
	git tag "$$NEXT_TAG"; \
	git push origin "$$NEXT_TAG"; \
	echo "Pushed $$NEXT_TAG"

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

backup-prod-now:
	$(MAKE) check-prod-env
	$(PROD_COMPOSE) run --rm postgres-backup backup-once

check-release-image-tag:
	@: "$${APP_IMAGE_TAG:?APP_IMAGE_TAG must be set or HEAD must point exactly at a release tag}"
	@echo "Production image tag: $(APP_IMAGE_TAG)"

current-prod-image-sha:
	@container_id="$$(APP_IMAGE_TAG=inspect $(PROD_COMPOSE) ps -q php)"; \
	if [ -z "$$container_id" ]; then \
		echo "Production PHP container is not running." >&2; \
		exit 1; \
	fi; \
	image_sha="$$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$$container_id")"; \
	if [ -z "$$image_sha" ] || [ "$$image_sha" = "<no value>" ]; then \
		echo "Running production PHP image has no revision label." >&2; \
		exit 1; \
	fi; \
	printf '%s\n' "$$image_sha"

pull-prod-images:
	$(MAKE) check-release-image-tag
	$(PROD_COMPOSE) pull $(PROD_APP_SERVICES)

migrate-prod-image:
	$(MAKE) check-release-image-tag
	$(PROD_COMPOSE) run --rm --no-deps php php bin/console --env=prod --no-debug doctrine:migrations:migrate -n

rollout-prod-postgres-backup:
	$(PROD_MONITORING_COMPOSE) build postgres-backup
	$(PROD_MONITORING_COMPOSE) up -d --no-deps --wait --wait-timeout 90 postgres-backup

switch-prod-app:
	$(MAKE) check-release-image-tag
	$(PROD_MONITORING_COMPOSE) up -d --no-deps --pull never --wait --wait-timeout 90 $(PROD_APP_SERVICES)

smoke-prod:
	@attempt=1; \
	while [ "$$attempt" -le 10 ]; do \
		if $(PROD_COMPOSE) exec -T nginx wget -q -O /dev/null http://127.0.0.1:8080/metrics; then \
			echo "Production HTTP smoke passed."; \
			exit 0; \
		fi; \
		attempt=$$((attempt + 1)); \
		sleep 2; \
	done; \
	echo "Production HTTP smoke failed." >&2; \
	exit 1

deploy-prod:
	$(MAKE) check-prod-env
	$(MAKE) check-loki-driver
	$(MAKE) check-monitoring-env
	$(MAKE) pull-prod-images
	$(MAKE) migrate-prod-image
	$(MAKE) rollout-prod-postgres-backup
	$(MAKE) switch-prod-app
	$(MAKE) smoke-prod

rollback-prod:
	$(MAKE) check-prod-env
	$(MAKE) check-loki-driver
	$(MAKE) check-monitoring-env
	$(MAKE) pull-prod-images
	$(MAKE) switch-prod-app
	$(MAKE) smoke-prod
