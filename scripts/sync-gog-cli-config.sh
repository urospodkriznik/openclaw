#!/usr/bin/env bash
# Copy host gogcli state into OPENCLAW_GOGCLI_CONFIG_DIR and chown for the gateway
# container (UID 1000 / user "node"). Required because bind-mounting ~/.config/gogcli
# owned only by your SSH user makes gog inside Docker hit "permission denied".
#
# Run on the VM after `gog auth` (or whenever tokens/credentials change), from repo root:
#   ./scripts/sync-gog-cli-config.sh
# Then: ./scripts/reown-openclaw-mounts.sh --container && ./scripts/docker-compose.sh restart openclaw-gateway
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

SRC="${GOGCLI_SOURCE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gogcli}"
DST_REL="${OPENCLAW_GOGCLI_CONFIG_DIR:-./.openclaw-gog-config}"
if [[ "$DST_REL" == /* ]]; then
  DST="$DST_REL"
else
  DST="$ROOT_DIR/$DST_REL"
fi

if [[ ! -d "$SRC" ]]; then
  echo "sync-gog-cli-config: source missing: $SRC (set GOGCLI_SOURCE_DIR or run gog auth on the host first)" >&2
  exit 1
fi

mkdir -p "$DST"

if ! command -v sudo >/dev/null 2>&1; then
  echo "sync-gog-cli-config: sudo is required to chown data for container UID 1000" >&2
  exit 1
fi

echo "sync-gog-cli-config: rsync $SRC/ -> $DST/"
sudo rsync -a "$SRC/" "$DST/"
echo "sync-gog-cli-config: chown -R 1000:1000 $DST"
sudo chown -R 1000:1000 "$DST"
echo "sync-gog-cli-config: done. Restart gateway if it is already running."
