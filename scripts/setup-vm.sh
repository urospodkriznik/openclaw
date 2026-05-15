#!/usr/bin/env bash
# One-shot GCP VM setup: host deps (optional), bootstrap, GSM fetch, production compose, Telegram, healthz.
#
# Prereqs: Ubuntu 24.04 VM, git clone, filled .env (USE_GSM_SECRETS=true typical). Docker installed
# or INSTALL_HOST_DEPS=1 with sudo. Not for macOS local dev — use make init.
#
# Usage:
#   make init-vm
#   INSTALL_HOST_DEPS=1 make init-vm   # also run setup-server.sh + install-docker.sh (sudo)
#
# Env: SKIP_GOG=1 SKIP_TELEGRAM=1 SKIP_PULL=1 SETUP_NO_RECREATE=1 INSTALL_HOST_DEPS=1
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_PROD=(./scripts/docker-compose.sh)

# shellcheck source=lib/required-env.sh
source "$ROOT_DIR/scripts/lib/required-env.sh"

step() { echo ""; echo "==> $*"; }

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "setup-vm: required command not found: $c" >&2
      exit 1
    }
  done
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "setup-vm: missing $ENV_FILE — run: make init-vm" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [[ -f "$ROOT_DIR/.env.generated" ]]; then
    # shellcheck disable=SC1090
    source "$ROOT_DIR/.env.generated"
  fi
  set +a
}

print_missing_env_vars() {
  echo "Still need values in $ENV_FILE:"
  printf '  • %s\n' "${MISSING_ENV_VARS[@]}"
  echo ""
  echo "Then run: make init-vm"
}

check_env_filled() {
  collect_missing_env_vars vm
  if ((${#MISSING_ENV_VARS[@]} > 0)); then
    print_missing_env_vars >&2
    exit 1
  fi
}

preflight_env_only() {
  [[ -f "$ENV_FILE" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  collect_missing_env_vars vm
  if ((${#MISSING_ENV_VARS[@]} > 0)); then
    print_missing_env_vars
    return 1
  fi
  if ! docker_preflight_ok; then
    return 1
  fi
  return 0
}

docker_preflight_ok() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  echo "Docker is not installed or not running on this VM."
  if truthy "${INSTALL_HOST_DEPS:-0}"; then
    echo "  Re-run with INSTALL_HOST_DEPS=1 (needs sudo) or run:"
  else
    echo "  Run once (sudo):"
  fi
  echo "    sudo ./scripts/setup-server.sh"
  echo "    sudo ./scripts/install-docker.sh"
  echo "  Or: INSTALL_HOST_DEPS=1 make init-vm"
  echo ""
  return 1
}

ensure_host_deps() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  if ! truthy "${INSTALL_HOST_DEPS:-0}"; then
    docker_preflight_ok
    exit 1
  fi
  step "Install host packages (setup-server.sh)"
  sudo ./scripts/setup-server.sh
  step "Install Docker (install-docker.sh)"
  sudo ./scripts/install-docker.sh
  if ! groups | tr ' ' '\n' | grep -qx docker 2>/dev/null; then
    echo "setup-vm: add your user to the docker group, then log out/in:" >&2
    echo "  sudo usermod -aG docker \"\$USER\"" >&2
  fi
}

docker_ready() {
  docker info >/dev/null 2>&1 || {
    echo "setup-vm: Docker daemon not reachable. Start docker: sudo systemctl start docker" >&2
    exit 1
  }
}

host_gogcli_source() {
  if [[ -n "${GOGCLI_SOURCE_DIR:-}" && -f "${GOGCLI_SOURCE_DIR}/credentials.json" ]]; then
    printf '%s' "${GOGCLI_SOURCE_DIR}"
    return 0
  fi
  if [[ -f "${HOME}/.config/gogcli/credentials.json" ]]; then
    printf '%s' "${HOME}/.config/gogcli"
    return 0
  fi
  if [[ -f "${HOME}/Library/Application Support/gogcli/credentials.json" ]]; then
    printf '%s' "${HOME}/Library/Application Support/gogcli"
    return 0
  fi
  return 1
}

telegram_configured() {
  local cfg="${OPENCLAW_CONFIG_DIR:-./.openclaw-config}/openclaw.json"
  [[ -f "$cfg" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e '.channels.telegram.enabled == true' "$cfg" >/dev/null 2>&1
}

detect_gog_arch() {
  if [[ -n "${GOG_LINUX_ARCH:-}" ]]; then
    return 0
  fi
  case "$(uname -m)" in
    arm64 | aarch64) export GOG_LINUX_ARCH=arm64 ;;
    *) export GOG_LINUX_ARCH=amd64 ;;
  esac
}

# --- main ---

if [[ "${1:-}" == "--preflight-only" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    exit 1
  fi
  preflight_env_only
  exit $?
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "setup-vm: this target is for a Linux GCP VM, not macOS. Use: make init" >&2
  exit 1
fi

need_cmd git
ensure_host_deps
need_cmd docker jq curl
load_env
check_env_filled
docker_ready

step "Fix mount ownership on host (deploy user ↔ container UID 1000)"
./scripts/reown-openclaw-mounts.sh --host || true

step "Bootstrap OpenClaw config"
./scripts/bootstrap-config.sh

step "Align Gmail watcher env (if hooks enabled)"
./scripts/align-gmail-watcher-env.sh

step "Validate .env"
./scripts/validate-env.sh

step "Fetch runtime secrets from Secret Manager (no-op when USE_GSM_SECRETS=false)"
./scripts/fetch-secrets-gsm.sh
load_env

if ! truthy "${SKIP_GOG:-0}"; then
  step "Install Linux gog for containers"
  detect_gog_arch
  ./scripts/install-gog-linux-for-docker.sh
  if src="$(host_gogcli_source)"; then
    step "Sync host gogcli from $src"
    ./scripts/sync-gog-cli-config.sh
  else
    echo "setup-vm: no host gogcli yet — skip sync (optional: gog auth, then make sync-gog-config && make restart)."
  fi
else
  echo "setup-vm: SKIP_GOG=1"
fi

step "Pull OpenClaw image (production compose)"
if ! truthy "${SKIP_PULL:-0}"; then
  "${COMPOSE_PROD[@]}" pull
fi

step "Fix mount ownership for container user"
./scripts/reown-openclaw-mounts.sh --container || true

step "Start gateway (production docker-compose.yml)"
if truthy "${SETUP_NO_RECREATE:-0}"; then
  "${COMPOSE_PROD[@]}" up -d
else
  "${COMPOSE_PROD[@]}" up -d --force-recreate
fi
sleep 5
./scripts/push-gogcli-to-gateway.sh || true

if ! truthy "${SKIP_TELEGRAM:-0}" && [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  if telegram_configured; then
    step "Telegram already enabled — refreshing token"
  else
    step "Register Telegram channel"
  fi
  "${COMPOSE_PROD[@]}" run -T --rm openclaw-cli \
    channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"
elif truthy "${SKIP_TELEGRAM:-0}"; then
  echo "setup-vm: SKIP_TELEGRAM=1"
else
  echo "setup-vm: no TELEGRAM_BOT_TOKEN (set in .env or via GSM → .env.generated)" >&2
  exit 1
fi

step "Health check"
./scripts/healthcheck.sh

echo ""
echo "setup-vm: done."
echo ""
echo "Next:"
echo "  • Telegram: send ping to your bot; /approve if pairing is required"
echo "  • Updates:  make deploy   (git pull + restart on this VM)"
echo "  • Logs:     make logs"
echo "  • Restart:  make restart  (production compose, force-recreate + gog push)"
