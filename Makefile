SHELL := /bin/sh

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

.PHONY: up composer-install php-rebuild php phpstan cs-fix rector k6 worker dmm

up:
	docker compose up -d --build
	$(MAKE) composer-install
	$(MAKE) dmm
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"

composer-install:
	docker compose exec -T php composer install --no-interaction --prefer-dist

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
