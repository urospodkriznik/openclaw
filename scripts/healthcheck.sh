#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null
echo "healthcheck: /healthz OK on port $PORT"
