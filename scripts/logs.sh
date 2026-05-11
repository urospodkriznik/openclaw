#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TAIL="${LOG_TAIL:-100}"
docker compose -f docker-compose.yml logs -f --tail="$TAIL" openclaw-gateway
