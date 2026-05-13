#!/usr/bin/env bash
# Copy host gogcli state into OPENCLAW_GOGCLI_CONFIG_DIR and chown for the gateway
# container (UID 1000 / user "node"). Required because bind-mounting ~/.config/gogcli
# owned only by your SSH user makes gog inside Docker hit "permission denied".
#
# Uses the same passwordless sudo pattern as reown-openclaw-mounts.sh: only `chown`
# is invoked via sudo -n. Copies with `rsync` when installed, otherwise `tar` (no sudo copy).
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

CHOWN_BIN="$(command -v chown || true)"
if [[ -z "$CHOWN_BIN" ]]; then
  echo "sync-gog-cli-config: chown not found in PATH" >&2
  exit 1
fi

need_sudo_chown() {
  if ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  if sudo -n "$CHOWN_BIN" --help >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

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

# After a previous sync, $DST is often 1000:1000 — reclaim so we can copy as you (no sudo copy).
if [[ ! -w "$DST" ]]; then
  if ! need_sudo_chown; then
    echo "sync-gog-cli-config: $DST is not writable by $(id -un); passwordless sudo for this exact binary is required:" >&2
    echo "  $(id -un) ALL=(ALL) NOPASSWD: $CHOWN_BIN" >&2
    echo "  (same as docs/GITHUB_ACTIONS.md for ./scripts/reown-openclaw-mounts.sh)" >&2
    exit 1
  fi
  echo "sync-gog-cli-config: reclaim $DST -> $(id -un):$(id -gn) (for copy)"
  sudo -n "$CHOWN_BIN" -R "$(id -un):$(id -gn)" "$DST"
fi

copy_gogcli_tree() {
  if command -v rsync >/dev/null 2>&1; then
    echo "sync-gog-cli-config: rsync $SRC/ -> $DST/"
    rsync -a "$SRC/" "$DST/"
  elif command -v tar >/dev/null 2>&1; then
    echo "sync-gog-cli-config: tar copy $SRC/ -> $DST/ (rsync not installed; optional: sudo apt install rsync)"
    (cd "$SRC" && tar cf - .) | (cd "$DST" && tar xf -)
  else
    echo "sync-gog-cli-config: install rsync or tar (e.g. sudo apt install -y rsync)" >&2
    exit 1
  fi
}

copy_gogcli_tree

if ! need_sudo_chown; then
  echo "sync-gog-cli-config: passwordless sudo required for $CHOWN_BIN to set UID 1000 ownership" >&2
  echo "  $(id -un) ALL=(ALL) NOPASSWD: $CHOWN_BIN" >&2
  exit 1
fi
echo "sync-gog-cli-config: chown -R 1000:1000 $DST"
sudo -n "$CHOWN_BIN" -R 1000:1000 "$DST"
echo "sync-gog-cli-config: done. Restart gateway if it is already running."
