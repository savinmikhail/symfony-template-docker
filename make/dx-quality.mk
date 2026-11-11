.PHONY: docker-image-audit frontend-build frontend-lint frontend-stylelint frontend-ci-install frontend-ci-quality phpstan phpat dep-analyse cs-fix cs-check rector rector-check composer-validate composer-audit prod-di-validate doctrine-schema-validate backend-quality test quality quality-dr kics kics-high kics-full k6 image-scout production-image-security postgres-metrics-test

docker-image-audit:
	DOCKER_AUDIT_DOCKERFILE="$(DOCKER_AUDIT_DOCKERFILE)" \
	DOCKER_AUDIT_TARGET="$(DOCKER_AUDIT_TARGET)" \
	DOCKER_AUDIT_IMAGE="$(DOCKER_AUDIT_IMAGE)" \
	DOCKER_AUDIT_CONTEXT="$(DOCKER_AUDIT_CONTEXT)" \
	DOCKER_AUDIT_DIR="$(DOCKER_AUDIT_DIR)" \
	./docker/audit-image-build.sh $(DOCKER_AUDIT_BUILD_ARGS)

frontend-build:
	docker compose exec -T frontend npm run build

frontend-lint:
	docker compose exec -T frontend npm run lint

frontend-stylelint:
	docker compose exec -T frontend npm run stylelint

frontend-ci-install:
	cd frontend && npm ci

frontend-ci-quality:
	cd frontend && node --test scripts/audit-exception.test.mjs && node scripts/audit-exception.mjs
	cd frontend && npm run lint
	cd frontend && npm run stylelint
	cd frontend && npm run build

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
	docker compose exec -T -e OTEL_PHP_AUTOLOAD_ENABLED=true -e OTEL_TRACES_EXPORTER=otlp -e OTEL_METRICS_EXPORTER=none -e OTEL_LOGS_EXPORTER=none php php -r 'require "vendor/autoload.php"; exit(OpenTelemetry\API\Globals::tracerProvider() instanceof OpenTelemetry\SDK\Trace\TracerProvider ? 0 : 1);'
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

test:
	docker compose exec -T php php bin/console --env=test doctrine:database:create --if-not-exists --no-interaction
	docker compose exec -T php php bin/console --env=test doctrine:migrations:migrate -n
	$(MAKE) doctrine-schema-validate
	docker compose exec -T -e APP_ENV=test -e APP_DEBUG=1 php php bin/phpunit

quality:
	$(MAKE) frontend-ci-install
	$(MAKE) frontend-ci-quality
	$(MAKE) backend-quality
	$(MAKE) postgres-metrics-test
	$(MAKE) test
	$(MAKE) production-image-security

quality-dr: quality

kics:
	$(MAKE) kics-high

kics-high:
	docker run --rm -v "$$PWD:/path" $(KICS_IMAGE) scan -p /path --exclude-paths $(KICS_EXCLUDE_PATHS) --exclude-severities $(KICS_HIGH_EXCLUDE_SEVERITIES) --no-progress

kics-full:
	docker run --rm -v "$$PWD:/path" $(KICS_IMAGE) scan -p /path --exclude-paths $(KICS_EXCLUDE_PATHS) --exclude-severities $(KICS_FULL_EXCLUDE_SEVERITIES) --no-progress

k6:
	docker compose run --rm k6

image-scout:
	@test -n "$(IMAGE)" || { echo 'Usage: make image-scout IMAGE=<local-production-image>' >&2; exit 1; }
	$(SCOUT) cves --only-severity critical,high --only-fixed --exit-code "local://$(IMAGE)"

production-image-security:
	python3 scripts/tests/image_security_test.py
	./docker/audit-image-security.sh symfony-template-security-php:local docker/php/Dockerfile prod
	./docker/audit-image-security.sh symfony-template-security-nginx:local docker/nginx/Dockerfile prod

postgres-metrics-test:
	sh docker/postgres/tests/statements-metrics-test.sh
