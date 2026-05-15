#!/usr/bin/env bash
# Stop OpenClaw containers and remove bind-mounted state for a clean VM reinstall.
# Does not remove the git clone or .env unless --full.
#
# Usage (from repo root):
#   ./scripts/wipe-vm-state.sh              # keep .env
#   ./scripts/wipe-vm-state.sh --prune-docker # also docker system prune -f
#   ./scripts/wipe-vm-state.sh --full         # remove .env and .env.generated too
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
KEEP_ENV=1
PRUNE_DOCKER=0

for arg in "$@"; do
  case "$arg" in
    --full) KEEP_ENV=0 ;;
    --prune-docker) PRUNE_DOCKER=1 ;;
    -h | --help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *)
      echo "wipe-vm-state: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-./.openclaw-config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./workspace}"
IMAP_DIR="${OPENCLAW_IMAP_SMTP_CONFIG_DIR:-./.openclaw-imap-smtp}"
GOG_DIR="${OPENCLAW_GOGCLI_CONFIG_DIR:-./.openclaw-gog-config}"
HOST_BIN="${ROOT_DIR}/.openclaw-host-bin"

echo "wipe-vm-state: stopping containers (production compose)…"
./scripts/docker-compose.sh down --remove-orphans 2>/dev/null || true
if [[ -f docker-compose.dev.yml ]]; then
  ./scripts/docker-compose.sh -f docker-compose.dev.yml down --remove-orphans 2>/dev/null || true
fi

echo "wipe-vm-state: removing local OpenClaw state dirs…"
rm -rf "$CONFIG_DIR" "$WORKSPACE_DIR" "$IMAP_DIR" "$GOG_DIR"
rm -rf "${HOST_BIN:?}"/*

if ((KEEP_ENV == 0)); then
  echo "wipe-vm-state: removing .env and .env.generated…"
  rm -f "$ENV_FILE" "$ROOT_DIR/.env.generated"
else
  echo "wipe-vm-state: keeping $ENV_FILE (use --full to delete)"
  rm -f "$ROOT_DIR/.env.generated"
fi

if ((PRUNE_DOCKER == 1)); then
  echo "wipe-vm-state: docker system prune -f…"
  docker system prune -f
fi

echo "wipe-vm-state: done. Next: edit .env (new Telegram GSM secret, LLM_PROVIDER=google), then make init-vm"
