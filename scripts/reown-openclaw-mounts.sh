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
IMAP_SMTP_DIR="${OPENCLAW_IMAP_SMTP_CONFIG_DIR:-./.openclaw-imap-smtp}"
GOG_STAGING_DIR="${OPENCLAW_GOGCLI_CONFIG_DIR:-./.openclaw-gog-config}"
HOST_BIN_DIR="${ROOT_DIR}/.openclaw-host-bin"

usage() {
  echo "usage: $0 --host | --container" >&2
  exit 1
}

[[ "${1:-}" == "--host" ]] || [[ "${1:-}" == "--container" ]] || usage

# NOPASSWD in sudoers must match the real chown path (often /usr/bin/chown on Ubuntu, /bin/chown elsewhere).
CHOWN_BIN="$(command -v chown || true)"
if [[ -z "$CHOWN_BIN" ]]; then
  echo "reown-openclaw-mounts: chown not found in PATH" >&2
  exit 1
fi

# Do not use "sudo -n true": sudoers like "NOPASSWD: /usr/bin/chown" do not cover /usr/bin/true.
need_sudo_chown() {
  if ! command -v sudo >/dev/null 2>&1; then
    return 1
  fi
  if sudo -n "$CHOWN_BIN" --help >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

host_mount_paths() {
  printf '%s\n' "$CONFIG_DIR" "$WORKSPACE_DIR" "$IMAP_SMTP_DIR" "$GOG_STAGING_DIR" "$HOST_BIN_DIR"
}

mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR" "$IMAP_SMTP_DIR" "$GOG_STAGING_DIR" "$HOST_BIN_DIR"

# Deploy user edits on the host; default = owner of this repo (not root when invoked via sudo bash -c).
host_owner() {
  if [[ -n "${OPENCLAW_DEPLOY_USER:-}" ]]; then
    printf '%s' "$OPENCLAW_DEPLOY_USER"
    return
  fi
  local u
  u="$(stat -c '%U' "$ROOT_DIR" 2>/dev/null || stat -f '%Su' "$ROOT_DIR" 2>/dev/null || true)"
  if [[ -n "$u" && "$u" != "UNKNOWN" ]]; then
    printf '%s' "$u"
    return
  fi
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    printf '%s' "$SUDO_USER"
    return
  fi
  id -un
}

host_group() {
  local u g
  u="$(host_owner)"
  g="$(id -gn "$u" 2>/dev/null || true)"
  printf '%s' "${g:-$u}"
}

path_writable_by_user() {
  local u="$1" p="$2"
  if [[ "$(id -un)" == "$u" ]]; then
    [[ -w "$p" ]]
    return
  fi
  sudo -u "$u" test -w "$p" 2>/dev/null
}

if [[ "$1" == "--host" ]]; then
  owner="$(host_owner)"
  group="$(host_group)"
  p=""
  need_reown=0
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    if ! path_writable_by_user "$owner" "$p"; then
      need_reown=1
      break
    fi
  done < <(host_mount_paths)
  if (( ! need_reown )); then
    echo "reown-openclaw-mounts: bind-mount paths already writable by $owner"
    exit 0
  fi
  if ! need_sudo_chown; then
    echo "reown-openclaw-mounts: not writable by $owner; passwordless sudo required for this exact binary:" >&2
    echo "  $(id -un) ALL=(ALL) NOPASSWD: $CHOWN_BIN" >&2
    echo "Or run once: sudo $CHOWN_BIN -R $owner:$group $CONFIG_DIR $WORKSPACE_DIR $IMAP_SMTP_DIR $GOG_STAGING_DIR $HOST_BIN_DIR" >&2
    exit 1
  fi
  echo "reown-openclaw-mounts: chown bind-mount paths -> $owner:$group (for bootstrap / cleanup)"
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    sudo -n "$CHOWN_BIN" -R "$owner:$group" "$p"
  done < <(host_mount_paths)
  chmod 755 "$CONFIG_DIR" 2>/dev/null || true
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
echo "reown-openclaw-mounts: chown bind-mount paths -> 1000:1000 (for container)"
while IFS= read -r p; do
  [[ -e "$p" ]] || continue
  sudo -n "$CHOWN_BIN" -R 1000:1000 "$p"
done < <(host_mount_paths)
