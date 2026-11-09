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
DOCKER_AUDIT_DOCKERFILE ?= docker/php/Dockerfile
DOCKER_AUDIT_TARGET ?= prod
DOCKER_AUDIT_IMAGE ?= symfony-template-audit:local
DOCKER_AUDIT_CONTEXT ?= .
DOCKER_AUDIT_DIR ?=
DOCKER_AUDIT_BUILD_ARGS ?=
SECRET_LENGTH ?= 32
APP_SECRET_LENGTH ?= 64
GEN_SECRETS_SCRIPT := ./docker/generate-secrets.sh
GEN_SECRETS_VARS := POSTGRES_PASSWORD RABBITMQ_DEFAULT_PASS APP_GRAFANA_ADMIN_PASSWORD APP_SECRET

HOST_UID ?= $(shell id -u)
HOST_GID ?= $(shell id -g)
APP_VERSION ?= $(shell git describe --tags --exact-match 2>/dev/null || echo dev)
READONLY_POSTGRES_USER ?= llm
PROD_SSH_HOST ?=
PROD_DEPLOY_PATH ?=
SSH ?= ssh
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

.DEFAULT_GOAL := up

include make/local.mk
include make/dx-quality.mk
include make/ci.mk
include make/deployments.mk
include make/data-ops.mk
