#!/usr/bin/env bash
# Stop OpenClaw containers and remove bind-mounted state for a clean VM reinstall.
# Does not remove the git clone or .env unless --full.
#
# Usage (from repo root):
#   ./scripts/wipe-vm-state.sh
#   ./scripts/wipe-vm-state.sh --prune-docker
#   ./scripts/wipe-vm-state.sh --full
#
# If removal fails (UID 1000 owned files), run as a sudo user:
#   sudo bash -c 'cd /path/to/oc_uros && ./scripts/wipe-vm-state.sh'
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
KEEP_ENV=1
PRUNE_DOCKER=0
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --full) KEEP_ENV=0; EXTRA_ARGS+=("$arg") ;;
    --prune-docker) PRUNE_DOCKER=1; EXTRA_ARGS+=("$arg") ;;
    -h | --help)
      sed -n '1,14p' "$0"
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

state_paths() {
  printf '%s\n' "$CONFIG_DIR" "$WORKSPACE_DIR" "$IMAP_DIR" "$GOG_DIR"
}

# Remove paths; recover when Docker left them owned by UID 1000.
remove_state_paths() {
  local paths=()
  local p
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    paths+=("$p")
  done < <(state_paths)

  if ((${#paths[@]} == 0)); then
    return 0
  fi

  if rm -rf "${paths[@]}" 2>/dev/null; then
    return 0
  fi

  echo "wipe-vm-state: permission denied removing state (often owned by UID 1000)." >&2

  # Running as root (e.g. sudo bash -c 'cd repo && ./scripts/wipe-vm-state.sh')
  if [[ "$(id -u)" -eq 0 ]]; then
    if [[ -x ./scripts/reown-openclaw-mounts.sh ]]; then
      ./scripts/reown-openclaw-mounts.sh --host || true
    fi
    rm -rf "${paths[@]}"
    return 0
  fi

  # Deploy user with passwordless sudo
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    echo "wipe-vm-state: retrying with sudo…"
    if sudo -n bash -c "cd '$ROOT_DIR' && ./scripts/reown-openclaw-mounts.sh --host"; then
      rm -rf "${paths[@]}" && return 0
    fi
    sudo -n rm -rf "${paths[@]}"
    return 0
  fi

  echo "" >&2
  echo "wipe-vm-state: cannot delete bind-mount data as $(id -un)." >&2
  echo "Ask an admin (e.g. urospodkriznik) to run:" >&2
  echo "  sudo bash -c 'cd $ROOT_DIR && ./scripts/wipe-vm-state.sh ${EXTRA_ARGS[*]}'" >&2
  exit 1
}

echo "wipe-vm-state: stopping containers (production compose)…"
./scripts/docker-compose.sh down --remove-orphans 2>/dev/null || true
if [[ -f docker-compose.dev.yml ]]; then
  ./scripts/docker-compose.sh -f docker-compose.dev.yml down --remove-orphans 2>/dev/null || true
fi

echo "wipe-vm-state: removing local OpenClaw state dirs…"
remove_state_paths
if [[ -d "$HOST_BIN" ]]; then
  find "$HOST_BIN" -mindepth 1 -delete 2>/dev/null || rm -rf "${HOST_BIN:?}"/* 2>/dev/null || true
fi

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

echo "wipe-vm-state: done. Next: edit .env (new Telegram GSM secret, LLM_PROVIDER=google), then SKIP_GOG=1 make init-vm"
