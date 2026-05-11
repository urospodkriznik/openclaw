#!/usr/bin/env bash
# Check out previous recorded git SHA and restart stack (best-effort).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STATE_DIR="${ROOT_DIR}/.deploy-state"
PREV="${STATE_DIR}/previous-sha"

if [[ ! -f "$PREV" ]]; then
  echo "No ${PREV} — cannot rollback." >&2
  exit 1
fi

TARGET="$(cat "$PREV")"
echo "rollback: resetting to $TARGET"

git fetch --all --quiet || true
git checkout --force "$TARGET"

docker compose -f docker-compose.yml pull
docker compose -f docker-compose.yml up -d

./scripts/healthcheck.sh || {
  echo "rollback: healthcheck still failing — inspect logs: make logs" >&2
  exit 1
}

echo "rollback: complete at $TARGET"
