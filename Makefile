SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

COMPOSE ?= docker compose
COMPOSE_FILES := -f docker-compose.yml
DEV_FILES := $(COMPOSE_FILES) -f docker-compose.dev.yml

.PHONY: setup dev up down restart logs health deploy rollback clean validate backup

setup:
	@./scripts/setup-server.sh

dev:
	@$(COMPOSE) $(DEV_FILES) up -d

up:
	@$(COMPOSE) $(COMPOSE_FILES) up -d

down:
	@$(COMPOSE) $(COMPOSE_FILES) down

restart:
	@$(COMPOSE) $(COMPOSE_FILES) up -d --force-recreate

logs:
	@./scripts/logs.sh

health:
	@./scripts/healthcheck.sh

deploy:
	@./scripts/deploy.sh

rollback:
	@./scripts/rollback.sh

clean:
	@$(COMPOSE) $(COMPOSE_FILES) down -v --remove-orphans || true

validate:
	@./scripts/validate-env.sh

backup:
	@./scripts/backup.sh
