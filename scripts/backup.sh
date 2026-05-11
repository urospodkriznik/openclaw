#!/usr/bin/env bash
# Tarball OpenClaw config directory (exclude large npm/plugin caches if present).
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

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-./.openclaw-config}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${ROOT_DIR}/backups"
mkdir -p "$OUT_DIR"
ARCHIVE="${OUT_DIR}/openclaw-config-${STAMP}.tar.gz"

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "No config dir at $CONFIG_DIR — nothing to back up."
  exit 0
fi

tar -czf "$ARCHIVE" \
  --exclude='*/node_modules/*' \
  --exclude='*/.npm/*' \
  -C "$(dirname "$CONFIG_DIR")" \
  "$(basename "$CONFIG_DIR")"

echo "backup: wrote $ARCHIVE"
