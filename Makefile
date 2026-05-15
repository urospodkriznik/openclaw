SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

COMPOSE ?= ./scripts/docker-compose.sh
COMPOSE_FILES :=
DEV_FILES := -f docker-compose.dev.yml

.PHONY: setup init init-vm setup-local setup-vm setup-gog setup-places wipe-vm dev local up down restart restart-dev restart-local logs health deploy deploy-all deploy-instances-init rollback clean validate backup sync-gog-config push-gog-gateway install-gog-linux verify-gog install-goplaces-linux verify-goplaces

# GCP VM base packages (sudo). For local Docker workstation use: make init
setup:
	@./scripts/setup-server.sh

# Fast path for new clones: scaffold .env → preflight → bootstrap → gog → up → Telegram → healthz
init:
	@./scripts/init-local.sh

setup-local:
	@./scripts/setup-local.sh

# GCP VM first boot (production compose, GSM, reown). Not for macOS — use make init.
init-vm:
	@./scripts/init-vm.sh

setup-vm:
	@./scripts/setup-vm.sh

# After host `gog auth` on a Linux VM: install ELF gog, sync, restart, verify (see docs/VM_QUICKSTART.md).
setup-gog:
	@./scripts/setup-gog-vm.sh

# Google Places (goplaces) on Linux VM — after GSM key or GOOGLE_PLACES_API_KEY in .env
setup-places:
	@./scripts/setup-places-vm.sh

# Remove containers + .openclaw-* state on a VM; keeps .env unless scripts/wipe-vm-state.sh --full
wipe-vm:
	@./scripts/wipe-vm-state.sh

dev:
	@$(COMPOSE) $(DEV_FILES) up -d --force-recreate
	@sleep 5
	@./scripts/push-gogcli-to-gateway.sh || true

# Same stack as `make dev`: local workstation (e.g. Mac) with relaxed memory/CPU — no GSM required.
# Prefer `make init` on first clone (also registers Telegram + gog). Use `make local` for a quick restart without full setup.
local:
	@$(COMPOSE) $(DEV_FILES) up -d --force-recreate
	@sleep 5
	@./scripts/push-gogcli-to-gateway.sh || true

up:
	@$(COMPOSE) $(COMPOSE_FILES) up -d

down:
	@$(COMPOSE) $(COMPOSE_FILES) down

# Recreates containers (safe). Do NOT use `docker compose restart` on this stack: openclaw-cli
# uses network_mode: service:openclaw-gateway; restarting only the gateway breaks that bind.
# Production VM / server (same compose as make deploy, without git pull).
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

# On the VM: deploy every path in deploy/instances.json (see docs/GITHUB_ACTIONS.md).
deploy-all:
	@./scripts/deploy-all.sh

# Create gitignored deploy/instances.json from the example (once per clone).
deploy-instances-init:
	@if [[ -f deploy/instances.json ]]; then \
	  echo "deploy/instances.json already exists"; \
	else \
	  cp deploy/instances.example.json deploy/instances.json && \
	  echo "Created deploy/instances.json — edit path/id, then commit is not needed (gitignored)."; \
	fi

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

install-goplaces-linux:
	@./scripts/install-goplaces-linux-for-docker.sh

verify-goplaces:
	@./scripts/verify-goplaces-in-container.sh -f docker-compose.dev.yml

sync-gog-config:
	@./scripts/sync-gog-cli-config.sh

# Docker Desktop (Mac): docker cp gogcli secrets into a running gateway (bind-mount stat fix).
push-gog-gateway:
	@./scripts/push-gogcli-to-gateway.sh
