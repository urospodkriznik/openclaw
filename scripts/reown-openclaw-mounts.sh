#!/usr/bin/env bash
# Fix ownership of bind-mounted OpenClaw paths between host (deploy user) and container (UID 1000).
# Used by deploy: --host before bootstrap, --container before docker compose up.
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
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./workspace}"

usage() {
  echo "usage: $0 --host | --container" >&2
  exit 1
}

[[ "${1:-}" == "--host" ]] || [[ "${1:-}" == "--container" ]] || usage

need_sudo_chown() {
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    return 0
  fi
  return 1
}

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"

if [[ "$1" == "--host" ]]; then
  if [[ -w "$CONFIG_DIR" ]] && [[ -w "$WORKSPACE_DIR" ]]; then
    echo "reown-openclaw-mounts: $CONFIG_DIR and $WORKSPACE_DIR already writable by $(id -un)"
    exit 0
  fi
  if ! need_sudo_chown; then
    echo "reown-openclaw-mounts: not writable by $(id -un); passwordless sudo required, e.g. in sudoers:" >&2
    echo "  $(id -un) ALL=(ALL) NOPASSWD: /bin/chown" >&2
    echo "Then run: sudo chown -R \"$(id -un):$(id -gn)\" \"$ROOT_DIR/$CONFIG_DIR\" \"$ROOT_DIR/$WORKSPACE_DIR\"" >&2
    exit 1
  fi
  echo "reown-openclaw-mounts: chown $CONFIG_DIR $WORKSPACE_DIR -> $(id -un):$(id -gn) (for bootstrap)"
  sudo -n chown -R "$(id -un):$(id -gn)" "$CONFIG_DIR" "$WORKSPACE_DIR"
  exit 0
fi

# --container: gateway image runs as UID 1000 (node)
if [[ "$(id -u)" -eq 1000 ]]; then
  echo "reown-openclaw-mounts: already UID 1000; skipping container chown"
  exit 0
fi
if ! need_sudo_chown; then
  echo "reown-openclaw-mounts: error: not UID 1000 and no passwordless sudo; the gateway container needs UID 1000 to read/write bind mounts." >&2
  echo "Configure NOPASSWD chown for this user, or see docs/TROUBLESHOOTING.md (EACCES)." >&2
  exit 1
fi
echo "reown-openclaw-mounts: chown $CONFIG_DIR $WORKSPACE_DIR -> 1000:1000 (for container)"
sudo -n chown -R 1000:1000 "$CONFIG_DIR" "$WORKSPACE_DIR"
