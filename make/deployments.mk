.PHONY: up-prod check-prod-env wait-prod composer-install-prod tag dmm-prod prod-cache-reset check-release-image-tag current-prod-image-sha pull-prod-images migrate-prod-image rollout-prod-postgres-backup switch-prod-app smoke-prod deploy-prod rollback-prod

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
	$(MAKE) provision-readonly-role
	@echo
	@echo "Production application is available at: http://localhost:$(APP_HTTP_PORT)/"

check-prod-env:
	@sh ./docker/verify-prod-env.sh prod

wait-prod:
	until $(PROD_COMPOSE) exec -T php php -v >/dev/null 2>&1; do sleep 2; done

composer-install-prod:
	$(PROD_COMPOSE) exec -T php sh -lc 'if [ -f vendor/autoload.php ]; then echo "Production dependencies are baked into the image."; else echo "Production image is missing vendor/autoload.php; rebuild and publish it from the Dockerfile." >&2; exit 1; fi'

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

dmm-prod:
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug doctrine:migration:migrate -n

prod-cache-reset:
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug cache:clear --no-warmup
	$(PROD_COMPOSE) exec -T php php bin/console --env=prod --no-debug cache:warmup

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
		if $(PROD_COMPOSE) exec -T nginx wget -q -O /dev/null http://127.0.0.1:8081/metrics; then \
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
	$(MAKE) provision-readonly-role
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

# Fresh vulnerability data: never wrap this target in a checksum/status cache.
SCOUT ?= docker scout
