SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

COMPOSE ?= ./scripts/docker-compose.sh
COMPOSE_FILES :=
DEV_FILES := -f docker-compose.dev.yml

.PHONY: setup dev up down restart logs health deploy rollback clean validate backup sync-gog-config

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

# After `gog auth` on the host: copy ~/.config/gogcli into OPENCLAW_GOGCLI_CONFIG_DIR and chown for UID 1000 (see docs/GOOGLE_INTEGRATIONS.md).
sync-gog-config:
	@./scripts/sync-gog-cli-config.sh
