#!/usr/bin/env bash
# Prove /usr/local/bin/gog inside gateway + CLI is Linux ELF (not Mach-O).
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
  if ! "${COMPOSE[@]}" exec -T "$svc" sh -lc 'test -f /usr/local/bin/gog' 2>/dev/null; then
    echo "  /usr/local/bin/gog: MISSING (gog compose overlay not loaded? run make install-gog-linux, use ./scripts/docker-compose.sh)" >&2
    return 1
  fi
  "${COMPOSE[@]}" exec -T "$svc" sh -lc 'ls -la /usr/local/bin/gog; echo -n "magic: "; head -c 4 /usr/local/bin/gog | od -An -tx1; gog version 2>&1 | head -1'
  echo ""
}

check_one openclaw-gateway
check_one openclaw-cli

echo "ELF magic should be: 7f 45 4c 46 (Mach-O starts with fe ed fa cf or cf fa ed fe on arm64)."
