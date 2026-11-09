.PHONY: suggest-free-ports check-free-ports up-monitoring grafana-alerting-provisioning check-loki-driver check-monitoring-env reload-prometheus gen-secrets worker dmm shell-postgres provision-readonly-role prod-query backup-prod-now monitoring-alerts-apply

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
	@mkdir -p $(GRAFANA_ALERTING_PROVISIONING_DIR)
	@cp docker/grafana/provisioning/alerting/*.yml $(GRAFANA_ALERTING_PROVISIONING_DIR)/
	@./docker/generate-grafana-alerting.sh $(GRAFANA_ALERTING_CONTACTPOINTS)

check-loki-driver:
	@docker plugin inspect loki >/dev/null 2>&1 || { \
		echo "Docker Loki logging driver is not installed." >&2; \
		echo "Install it first, for example: docker plugin install grafana/loki-docker-driver:3.7.0-<amd64|arm64> --alias loki --grant-all-permissions" >&2; \
		exit 1; \
	}

check-monitoring-env:
	@sh ./docker/verify-prod-env.sh monitoring

reload-prometheus:
	$(COMPOSE_CMD) kill --signal=HUP prometheus

gen-secrets:
	@SECRET_LENGTH=$(SECRET_LENGTH) APP_SECRET_LENGTH=$(APP_SECRET_LENGTH) $(GEN_SECRETS_SCRIPT) $(GEN_SECRETS_VARS)

worker:
	docker compose exec php php bin/console messenger:consume async -vv

dmm:
	docker compose exec php php bin/console doctrine:migration:migrate -n

shell-postgres:
	docker compose exec -T db psql -U $${POSTGRES_USER:-app} -d $${POSTGRES_DB:-app}

provision-readonly-role:
	docker compose exec -T db psql -U $${POSTGRES_USER:-app} -d $${POSTGRES_DB:-app} -f - < docker/postgres/init/002-readonly-role.sql

prod-query:
	@set -eu; \
	test -n "$(PROD_SSH_HOST)" || { echo 'Set PROD_SSH_HOST for this service.' >&2; exit 2; }; \
	test -n "$(PROD_DEPLOY_PATH)" || { echo 'Set PROD_DEPLOY_PATH for this service.' >&2; exit 2; }; \
	sql_file="$$(mktemp)"; \
	trap 'rm -f "$$sql_file"' EXIT INT TERM; \
	cat > "$$sql_file"; \
	if LC_ALL=C grep -Fq '\' "$$sql_file"; then \
		echo 'Backslashes are not allowed in agent SQL because psql treats them as client-side meta-commands.' >&2; \
		exit 7; \
	fi; \
	{ printf '%s\n' '\set ON_ERROR_STOP on'; cat "$$sql_file"; } | $(SSH) -T "$(PROD_SSH_HOST)" 'make -s -C "$(PROD_DEPLOY_PATH)" shell-postgres POSTGRES_USER="$(READONLY_POSTGRES_USER)"'

backup-prod-now:
	$(MAKE) check-prod-env
	$(PROD_COMPOSE) run --rm postgres-backup backup-once

monitoring-alerts-apply:
	@test -n "$(GRAFANA_CONTAINER)" || { echo "Set GRAFANA_CONTAINER to the existing product Grafana container" >&2; exit 2; }
	@python3 docker/apply-grafana-alerting.py --container "$(GRAFANA_CONTAINER)"

# Build layers may be cached; Scout advisory data is always refreshed.
