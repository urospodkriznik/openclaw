#!/usr/bin/env bash
# When ENABLE_GMAIL_HOOKS is true, ensure OPENCLAW_SKIP_GMAIL_WATCHER=0 on disk so
# validate-env and docker-compose agree (default skip=1 would disable the watcher).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  exit 0
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

truthy() {
  case "${1:-}" in
  1 | true | TRUE | yes | YES | on | ON) return 0 ;;
  *) return 1 ;;
  esac
}

if ! truthy "${ENABLE_GMAIL_HOOKS:-false}"; then
  exit 0
fi

# Match validate-env: unset or "1" means watcher is skipped — must flip to 0 for hooks.
if [[ "${OPENCLAW_SKIP_GMAIL_WATCHER:-1}" != "1" ]]; then
  exit 0
fi

tmp="${ENV_FILE}.tmp.$$"
grep -v '^OPENCLAW_SKIP_GMAIL_WATCHER=' "$ENV_FILE" >"$tmp" || true
mv "$tmp" "$ENV_FILE"
echo 'OPENCLAW_SKIP_GMAIL_WATCHER=0' >>"$ENV_FILE"
echo "align-gmail-watcher-env: ENABLE_GMAIL_HOOKS=true → set OPENCLAW_SKIP_GMAIL_WATCHER=0 in $ENV_FILE"
