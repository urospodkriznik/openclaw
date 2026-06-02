#!/usr/bin/env bash
# Append missing bootstrap-managed keys from .env.example → .env (never overwrites existing values).
# Lets git push ship new OPENCLAW_HEARTBEAT_* / HEALTHCHECK_* defaults to VMs on deploy.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
EXAMPLE="${ROOT_DIR}/.env.example"

if [[ ! -f "$EXAMPLE" ]]; then
  echo "sync-bootstrap-env-keys: missing $EXAMPLE" >&2
  exit 1
fi

touch "$ENV_FILE"

key_in_env() {
  local key="$1"
  grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null
}

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
  key="${line%%=*}"
  key="${key//[[:space:]]/}"
  key_in_env "$key" && continue
  echo "$line" >>"$ENV_FILE"
  echo "sync-bootstrap-env-keys: added $key to $ENV_FILE"
done < <(grep -E '^(OPENCLAW_HEARTBEAT_|OPENCLAW_AGENT_TIMEOUTS_|OPENCLAW_AGENT_TIMEOUT_|OPENCLAW_LLM_IDLE_|HEALTHCHECK_)' "$EXAMPLE")
