.PHONY: up composer-install frontend-install php-rebuild php

up:
	python3 docker/ensure-compose-network.py "$$(docker compose config --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
	docker compose up -d --build
	$(MAKE) composer-install
	$(MAKE) frontend-install
	$(MAKE) dmm
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"
	@echo "Frontend is available at: http://localhost:$(APP_FRONTEND_PORT)/"

composer-install:
	docker compose exec -T -u $(HOST_UID):$(HOST_GID) php sh -lc 'mkdir -p vendor && composer install --no-interaction --prefer-dist'

frontend-install:
	docker compose exec -T frontend npm install

php-rebuild:
	docker compose up -d --no-deps --build php
	@echo
	@echo "Application is available at: http://localhost:$(APP_HTTP_PORT)/"

php:
	docker compose exec php bash
