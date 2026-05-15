SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

COMPOSE ?= ./scripts/docker-compose.sh
COMPOSE_FILES :=
DEV_FILES := -f docker-compose.dev.yml

.PHONY: setup dev local up down restart restart-dev restart-local logs health deploy rollback clean validate backup sync-gog-config push-gog-gateway install-gog-linux verify-gog

setup:
	@./scripts/setup-server.sh

dev:
	@$(COMPOSE) $(DEV_FILES) up -d
	@sleep 5
	@./scripts/push-gogcli-to-gateway.sh || true

# Same stack as `make dev`: local workstation (e.g. Mac) with relaxed memory/CPU — no GSM required.
local:
	@$(COMPOSE) $(DEV_FILES) up -d
	@sleep 5
	@./scripts/push-gogcli-to-gateway.sh || true

up:
	@$(COMPOSE) $(COMPOSE_FILES) up -d

down:
	@$(COMPOSE) $(COMPOSE_FILES) down

# Recreates containers (safe). Do NOT use `docker compose restart` on this stack: openclaw-cli
# uses network_mode: service:openclaw-gateway; restarting only the gateway breaks that bind.
restart:
	@$(COMPOSE) $(COMPOSE_FILES) up -d --force-recreate
	@sleep 5
	@./scripts/push-gogcli-to-gateway.sh || true

restart-dev restart-local:
	@$(COMPOSE) $(DEV_FILES) up -d --force-recreate
	@sleep 5
	@./scripts/push-gogcli-to-gateway.sh || true

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
# Linux ELF gog for bind-mount into OpenClaw containers (macOS Homebrew gog is Mach-O — wrong OS).
install-gog-linux:
	@./scripts/install-gog-linux-for-docker.sh

verify-gog:
	@./scripts/verify-gog-in-container.sh -f docker-compose.dev.yml

sync-gog-config:
	@./scripts/sync-gog-cli-config.sh

# Docker Desktop (Mac): docker cp gogcli secrets into a running gateway (bind-mount stat fix).
push-gog-gateway:
	@./scripts/push-gogcli-to-gateway.sh
