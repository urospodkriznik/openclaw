#!/usr/bin/env bash
# Copy host gogcli state into OPENCLAW_GOGCLI_CONFIG_DIR and chown for the gateway
# container (UID 1000 / user "node"). Required because bind-mounting host gogcli data
# owned only by your login makes gog inside Docker hit "permission denied".
#
# Default source: GOGCLI_SOURCE_DIR if set, else ~/.config/gogcli (Linux / XDG),
# else ~/Library/Application Support/gogcli (macOS Homebrew gogcli).
#
# Uses sudo for chown: tries `sudo -n` first (CI / passwordless VM deploy). If that fails
# but stdin is a TTY (typical Mac Terminal), prompts once with interactive `sudo`. Copies with `rsync` when installed, otherwise `tar` (no sudo copy).
#
# Run on the VM after `gog auth` (or whenever tokens/credentials change), from repo root:
#   ./scripts/sync-gog-cli-config.sh
# Then: ./scripts/reown-openclaw-mounts.sh --container && ./scripts/docker-compose.sh up -d --force-recreate
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

# Try non-interactive sudo first; if stdin is a TTY, allow one password prompt (local Mac).
run_sudo_chown() {
  if sudo -n "$CHOWN_BIN" "$@" 2>/dev/null; then
    return 0
  fi
  if [[ -t 0 ]] && command -v sudo >/dev/null 2>&1; then
    echo "sync-gog-cli-config: sudo password required for: $CHOWN_BIN $*" >&2
    sudo "$CHOWN_BIN" "$@"
    return 0
  fi
  return 1
}

run_sudo_finalize_gogcli_mount() {
  local inner
  # Docker Desktop for Mac: com.apple.* xattrs on bind-mounted files can make Linux stat(2) fail
  # inside the container (ls shows "?????????", permission denied). Strip them after chown/chmod.
  inner='chown -R 1000:1000 "$SYNC_GOG_DST" && find "$SYNC_GOG_DST" -type d -exec chmod 755 {} + && find "$SYNC_GOG_DST" -type f -exec chmod 600 {} + && case "$(uname -s)" in Darwin) if command -v xattr >/dev/null 2>&1; then xattr -cr "$SYNC_GOG_DST" || exit 1; fi ;; esac'
  if sudo -n env SYNC_GOG_DST="$DST" sh -c "$inner" 2>/dev/null; then
    return 0
  fi
  if [[ -t 0 ]] && command -v sudo >/dev/null 2>&1; then
    echo "sync-gog-cli-config: sudo password required to chown/chmod $DST" >&2
    sudo env SYNC_GOG_DST="$DST" sh -c "$inner"
    return 0
  fi
  return 1
}

resolve_gogcli_source_dir() {
  if [[ -n "${GOGCLI_SOURCE_DIR:-}" ]] && [[ -d "$GOGCLI_SOURCE_DIR" ]]; then
    printf '%s' "$GOGCLI_SOURCE_DIR"
    return 0
  fi
  local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/gogcli"
  if [[ -d "$xdg" ]]; then
    printf '%s' "$xdg"
    return 0
  fi
  local macos="$HOME/Library/Application Support/gogcli"
  if [[ -d "$macos" ]]; then
    printf '%s' "$macos"
    return 0
  fi
  return 1
}

if ! SRC="$(resolve_gogcli_source_dir)"; then
  echo "sync-gog-cli-config: no gogcli config directory found. Tried:" >&2
  echo "  - GOGCLI_SOURCE_DIR (when set)" >&2
  echo "  - ${XDG_CONFIG_HOME:-$HOME/.config}/gogcli" >&2
  echo "  - $HOME/Library/Application Support/gogcli (macOS)" >&2
  echo "Run gog auth on the host first, or set GOGCLI_SOURCE_DIR to your gogcli data path." >&2
  exit 1
fi

echo "sync-gog-cli-config: using source $SRC"

DST_REL="${OPENCLAW_GOGCLI_CONFIG_DIR:-./.openclaw-gog-config}"
if [[ "$DST_REL" == /* ]]; then
  DST="$DST_REL"
else
  DST="$ROOT_DIR/$DST_REL"
fi

mkdir -p "$DST"

# After a previous sync, $DST is often 1000:1000 — reclaim so we can copy as you (no sudo copy).
if [[ ! -w "$DST" ]]; then
  echo "sync-gog-cli-config: reclaim $DST -> $(id -un):$(id -gn) (for copy)"
  if ! run_sudo_chown -R "$(id -un):$(id -gn)" "$DST"; then
    echo "sync-gog-cli-config: could not chown $DST to your user (passwordless sudo or interactive terminal required)" >&2
    echo "  For VMs: $(id -un) ALL=(ALL) NOPASSWD: $CHOWN_BIN" >&2
    echo "  Or run once: sudo \"$CHOWN_BIN\" -R \"$(id -un):$(id -gn)\" \"$DST\"" >&2
    exit 1
  fi
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

# Docker Desktop (Mac): even after xattr -cr, Linux in the VM sometimes still sees bind-mounted
# files as "?????????" (stat/open fail). Rewriting each file through a new inode before finalize
# clears that class of bugs; keep this Darwin-only so Linux hosts are unchanged.
darwin_rewrite_synced_files_for_bind_mount() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  echo "sync-gog-cli-config: Darwin — rewriting synced files (new inode; mitigates Docker Desktop bind-mount glitches in Linux)."
  local f t
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    t="$(mktemp "${TMPDIR:-/tmp}/gogcli-bind.XXXXXX")"
    cat "$f" >"$t" || {
      rm -f "$t"
      echo "sync-gog-cli-config: error: could not read $f" >&2
      exit 1
    }
    mv -f "$t" "$f" || {
      rm -f "$t"
      echo "sync-gog-cli-config: error: could not replace $f" >&2
      exit 1
    }
  done < <(find "$DST" -type f -print0)
}

darwin_rewrite_synced_files_for_bind_mount

# Container user must own the tree. Docker Desktop on macOS also needs your Mac user to be able
# to *traverse* the bind-mount source; mode 700 + owner 1000 otherwise yields misleading errors
# ("mkdir ... file exists") on restart. Dirs 755, files 600: host can open the mount path; secrets stay user-only.
echo "sync-gog-cli-config: chown 1000:1000 + chmod dirs 755, files 600 under $DST"
if ! run_sudo_finalize_gogcli_mount; then
  echo "sync-gog-cli-config: could not finalize ownership/modes (sudo required)." >&2
  echo "  Run from an interactive terminal, or VM: $(id -un) ALL=(ALL) NOPASSWD: $CHOWN_BIN" >&2
  exit 1
fi

# Docker Desktop / VirtioFS: Linux may still be unable to stat bind-mounted files. With a **named
# volume** for /home/node/.config/gogcli, push streams a tar from host staging via docker exec.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/push-gogcli-to-gateway.sh" || echo "sync-gog-cli-config: push-gogcli-to-gateway.sh failed — run it manually after the gateway is up." >&2
fi

echo "sync-gog-cli-config: done. Restart gateway if it is already running."
