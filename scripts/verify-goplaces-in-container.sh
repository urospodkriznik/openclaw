#!/usr/bin/env bash
# Prove /usr/local/bin/goplaces inside gateway + CLI is Linux ELF and GOOGLE_PLACES_API_KEY is set.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(./scripts/docker-compose.sh)
while [[ "${1:-}" == "-f" && -n "${2:-}" ]]; do
  COMPOSE+=( -f "$2" )
  shift 2
done

check_one() {
  local svc="$1"
  echo "=== $svc ==="
  if ! "${COMPOSE[@]}" exec -T "$svc" sh -lc 'test -f /usr/local/bin/goplaces' 2>/dev/null; then
    echo "  /usr/local/bin/goplaces: MISSING (run make install-goplaces-linux && make restart-dev)" >&2
    return 1
  fi
  "${COMPOSE[@]}" exec -T "$svc" sh -lc 'ls -la /usr/local/bin/goplaces; echo -n "magic: "; head -c 4 /usr/local/bin/goplaces | od -An -tx1; goplaces --help 2>&1 | head -1'
  "${COMPOSE[@]}" exec -T "$svc" sh -lc 'if test -n "${GOOGLE_PLACES_API_KEY:-}"; then echo "GOOGLE_PLACES_API_KEY: set (${#GOOGLE_PLACES_API_KEY} chars)"; else echo "GOOGLE_PLACES_API_KEY: EMPTY (set in .env and recreate)" >&2; exit 1; fi'
  echo ""
}

check_one openclaw-gateway
check_one openclaw-cli

echo "ELF magic should be: 7f 45 4c 46"
