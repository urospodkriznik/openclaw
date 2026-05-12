#!/usr/bin/env bash
# Pull latest git revision, validate, (re)start compose, healthcheck; record rollback SHA.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STATE_DIR="${ROOT_DIR}/.deploy-state"
mkdir -p "$STATE_DIR"

OLD_HEAD="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

git pull --ff-only

NEW_HEAD="$(git rev-parse HEAD)"

./scripts/reown-openclaw-mounts.sh --host
./scripts/bootstrap-config.sh
./scripts/validate-env.sh
./scripts/fetch-secrets-gsm.sh
./scripts/reown-openclaw-mounts.sh --container

docker compose -f docker-compose.yml pull
docker compose -f docker-compose.yml up -d

if ./scripts/healthcheck.sh; then
  echo "$OLD_HEAD" >"${STATE_DIR}/previous-sha"
  echo "$NEW_HEAD" >"${STATE_DIR}/current-sha"
  echo "deploy: success at $NEW_HEAD"
else
  echo "deploy: healthcheck failed after upgrade" >&2
  exit 1
fi
