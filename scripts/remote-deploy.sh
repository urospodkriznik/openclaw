#!/usr/bin/env bash
# Production deploy steps for the current repo directory (run on the VM after cd + git pull).
# Used by GitHub Actions, ./scripts/deploy.sh, and ./scripts/deploy-all.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INSTANCE_ID="${1:-}"

if [[ -n "$INSTANCE_ID" ]]; then
  echo "remote-deploy: instance=$INSTANCE_ID path=$ROOT_DIR"
fi

if [[ ! -f .env ]]; then
  echo "remote-deploy: missing .env in $ROOT_DIR — run make init-vm once for this instance." >&2
  exit 1
fi

# Per-instance ports must be set in .env (e.g. primary 18789, secondary 18791).
if grep -qE '^OPENCLAW_GATEWAY_PORT=' .env 2>/dev/null; then
  port="$(grep -E '^OPENCLAW_GATEWAY_PORT=' .env | tail -n1 | cut -d= -f2- | tr -d ' \"')"
  echo "remote-deploy: OPENCLAW_GATEWAY_PORT=${port:-18789}"
else
  echo "remote-deploy: warn: OPENCLAW_GATEWAY_PORT not set in .env (default 18789 may conflict across instances)" >&2
fi

export VALIDATION_LEVEL="${VALIDATION_LEVEL:-full}"

./scripts/reown-openclaw-mounts.sh --host
./scripts/bootstrap-config.sh
./scripts/align-gmail-watcher-env.sh
./scripts/validate-env.sh
./scripts/fetch-secrets-gsm.sh
./scripts/reown-openclaw-mounts.sh --container

./scripts/docker-compose.sh pull
./scripts/docker-compose.sh up -d --force-recreate
./scripts/push-gogcli-to-gateway.sh || true

if ! ./scripts/healthcheck.sh; then
  echo "remote-deploy: healthcheck failed — recent logs:" >&2
  ./scripts/docker-compose.sh logs --tail=120 openclaw-gateway >&2 || true
  exit 1
fi

echo "remote-deploy: OK ($ROOT_DIR)"
