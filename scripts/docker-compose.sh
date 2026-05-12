#!/usr/bin/env bash
# Run docker compose with docker-compose.yml plus docker-compose.gog.yml when the
# host gog binary exists (so openclaw-gateway and openclaw-cli both see /usr/local/bin/gog).
# Leading "-f <file>" pairs are forwarded after the baseline files (for dev overrides).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE" 2>/dev/null || true
  set +a
fi

GOG_PATH="${OPENCLAW_GOG_HOST_PATH:-/usr/local/bin/gog}"
compose_files=( -f docker-compose.yml )
if [[ -f "$GOG_PATH" ]]; then
  compose_files+=( -f docker-compose.gog.yml )
fi

extra=()
while [[ "${1:-}" == "-f" && -n "${2:-}" ]]; do
  extra+=( -f "$2" )
  shift 2
done

all_files=( "${compose_files[@]}" )
if ((${#extra[@]} > 0)); then
  all_files+=( "${extra[@]}" )
fi
exec docker compose "${all_files[@]}" "$@"
