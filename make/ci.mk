.PHONY: ci-pull-php ci-up-php ci-up-tests ci-down

ci-pull-php:
	$(CI_COMPOSE) pull php

ci-up-php:
	$(CI_COMPOSE) up -d --no-build --no-deps php

ci-up-tests:
	$(CI_COMPOSE) up -d --wait --no-build db redis rabbitmq php

ci-down:
	$(CI_COMPOSE) down -v
