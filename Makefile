SHELL := /bin/sh

PROD_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.prod.yml

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

.PHONY: up up-prod wait-prod composer-install composer-install-prod php-rebuild php phpstan cs-fix rector k6 worker dmm dmm-prod prod-cache-reset

up:
	docker compose up -d --build
	$(MAKE) composer-install
	$(MAKE) dmm
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"

up-prod:
	$(PROD_COMPOSE) up -d --build
	$(MAKE) wait-prod
	$(MAKE) composer-install-prod
	$(MAKE) prod-cache-reset
	$(MAKE) dmm-prod
	@echo
	@echo "Production application is available at: http://localhost:$(APP_HTTP_PORT)/"

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

cs-fix:
	docker compose exec php php tools/php-cs-fixer/vendor/bin/php-cs-fixer fix

rector:
	docker compose exec php php tools/rector/vendor/bin/rector process

k6:
	docker compose run --rm k6

worker:
	docker compose exec php php bin/console messenger:consume async -vv

dmm:
	docker compose exec php php bin/console doctrine:migration:migrate -n

dmm-prod:
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug doctrine:migration:migrate -n

prod-cache-reset:
	$(PROD_COMPOSE) exec -T -u 0:0 php sh -lc 'rm -rf var/cache/prod && mkdir -p var/cache/prod && chown -R www-data:www-data var/cache'
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug cache:warmup
