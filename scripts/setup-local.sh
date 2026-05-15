#!/usr/bin/env bash
# One-shot local workstation setup (Mac/Linux + Docker): bootstrap config, optional gog,
# pull image, start dev stack (recreate + gog push), register Telegram, healthcheck.
#
# Prereqs: Docker 24+ with Compose v2, jq, curl. Fill .env first (see .env.example).
#
# Usage (from repo root):
#   cp .env.example .env   # edit secrets
#   ./scripts/setup-local.sh
#   # or: make init
#
# Env overrides:
#   SKIP_GOG=1              Skip Linux gog download + sync/push
#   SKIP_GOPLACES=1         Skip Linux goplaces download + skill install
#   SKIP_TELEGRAM=1         Skip `channels add`
#   SKIP_PULL=1             Skip `docker compose pull`
#   SETUP_NO_RECREATE=1   Use `up -d` instead of `--force-recreate`
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_DEV=(./scripts/docker-compose.sh -f docker-compose.dev.yml)

# shellcheck source=lib/required-env.sh
source "$ROOT_DIR/scripts/lib/required-env.sh"

step() { echo ""; echo "==> $*"; }

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "setup-local: required command not found: $c" >&2
      exit 1
    }
  done
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "setup-local: missing $ENV_FILE" >&2
    echo "  Run: make init" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

print_missing_env_vars() {
  echo "Still need values in $ENV_FILE:"
  printf '  • %s\n' "${MISSING_ENV_VARS[@]}"
  echo ""
  echo "Then run: make init"
}

check_env_filled() {
  collect_missing_env_vars local
  if ((${#MISSING_ENV_VARS[@]} > 0)); then
    print_missing_env_vars >&2
    exit 1
  fi
}

preflight_env_only() {
  load_env
  collect_missing_env_vars local
  if ((${#MISSING_ENV_VARS[@]} > 0)); then
    print_missing_env_vars
    return 1
  fi
  return 0
}

docker_ready() {
  docker info >/dev/null 2>&1 || {
    echo "setup-local: Docker daemon is not running. Start Docker Desktop (or the docker service) and retry." >&2
    exit 1
  }
}

host_gogcli_source() {
  if [[ -n "${GOGCLI_SOURCE_DIR:-}" && -f "${GOGCLI_SOURCE_DIR}/credentials.json" ]]; then
    printf '%s' "${GOGCLI_SOURCE_DIR}"
    return 0
  fi
  if [[ -f "${HOME}/Library/Application Support/gogcli/credentials.json" ]]; then
    printf '%s' "${HOME}/Library/Application Support/gogcli"
    return 0
  fi
  if [[ -f "${HOME}/.config/gogcli/credentials.json" ]]; then
    printf '%s' "${HOME}/.config/gogcli"
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

detect_linux_bin_arch() {
  if [[ -n "${GOG_LINUX_ARCH:-}" && -n "${GOPLACES_LINUX_ARCH:-}" ]]; then
    return 0
  fi
  case "$(uname -m)" in
    arm64 | aarch64)
      : "${GOG_LINUX_ARCH:=arm64}"
      : "${GOPLACES_LINUX_ARCH:=arm64}"
      ;;
    *)
      : "${GOG_LINUX_ARCH:=amd64}"
      : "${GOPLACES_LINUX_ARCH:=amd64}"
      ;;
  esac
  export GOG_LINUX_ARCH GOPLACES_LINUX_ARCH
}

places_enabled() {
  [[ -n "${GOOGLE_PLACES_API_KEY:-}" ]]
}

# --- main ---

if [[ "${1:-}" == "--preflight-only" ]]; then
  preflight_env_only
  exit $?
fi

need_cmd docker jq curl
load_env
check_env_filled
docker_ready

step "Bootstrap OpenClaw config (openclaw.json + exec-approvals.json)"
./scripts/bootstrap-config.sh

step "Validate .env"
./scripts/validate-env.sh

if ! truthy "${SKIP_GOG:-0}"; then
  step "Install Linux ELF gog for Docker ($(uname -m) host → GOG_LINUX_ARCH=${GOG_LINUX_ARCH:-auto})"
  detect_linux_bin_arch
  ./scripts/install-gog-linux-for-docker.sh

  if src="$(host_gogcli_source)"; then
    step "Sync host gogcli from $src"
    ./scripts/sync-gog-cli-config.sh
  else
    echo "setup-local: no host gogcli credentials yet — skip sync (optional: run gog auth on the host, then make sync-gog-config && make restart-dev)."
  fi
else
  echo "setup-local: SKIP_GOG=1 — skipping gog install/sync."
fi

if ! truthy "${SKIP_GOPLACES:-0}"; then
  if places_enabled; then
    step "Install Linux ELF goplaces for Docker (GOPLACES_LINUX_ARCH=${GOPLACES_LINUX_ARCH:-auto})"
    detect_linux_bin_arch
    ./scripts/install-goplaces-linux-for-docker.sh
  else
    echo "setup-local: GOOGLE_PLACES_API_KEY empty — skipping goplaces (set key in .env, then make install-goplaces-linux && make restart-dev)."
  fi
else
  echo "setup-local: SKIP_GOPLACES=1 — skipping goplaces install."
fi

step "Pull OpenClaw image (skip with SKIP_PULL=1)"
if ! truthy "${SKIP_PULL:-0}"; then
  "${COMPOSE_DEV[@]}" pull
else
  echo "setup-local: SKIP_PULL=1"
fi

step "Start gateway stack (docker-compose.dev.yml)"
if truthy "${SETUP_NO_RECREATE:-0}"; then
  "${COMPOSE_DEV[@]}" up -d
  sleep 5
  ./scripts/push-gogcli-to-gateway.sh || true
else
  "${COMPOSE_DEV[@]}" up -d --force-recreate
  sleep 5
  ./scripts/push-gogcli-to-gateway.sh || true
fi

if ! truthy "${SKIP_TELEGRAM:-0}" && [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  if telegram_configured; then
    step "Telegram channel already enabled in openclaw.json — refreshing token via channels add"
  else
    step "Register Telegram channel"
  fi
  "${COMPOSE_DEV[@]}" run -T --rm openclaw-cli \
    channels add --channel telegram --token "$TELEGRAM_BOT_TOKEN"
else
  echo "setup-local: SKIP_TELEGRAM=1 or no TELEGRAM_BOT_TOKEN — skipping channels add."
fi

if places_enabled && ! truthy "${SKIP_GOPLACES:-0}" && [[ -f "${ROOT_DIR}/.openclaw-host-bin/goplaces" ]]; then
  step "Install goplaces skill (ClawHub)"
  if ! "${COMPOSE_DEV[@]}" run -T --rm openclaw-cli skills install goplaces; then
    echo "setup-local: goplaces skill install failed — retry after stack is up:" >&2
    echo "  ${COMPOSE_DEV[*]} run -T --rm openclaw-cli skills install goplaces" >&2
  fi
fi

step "Health check"
./scripts/healthcheck.sh

echo ""
echo "setup-local: done."
echo ""
echo "Next:"
echo "  • Telegram: message your bot (try ping). If pairing is required, approve with /approve in chat."
echo "  • Logs:     make logs"
echo "  • Restart:  make restart-dev   (recreate + gog push — use after .env or gog changes)"
if ! host_gogcli_source >/dev/null 2>&1 && ! truthy "${SKIP_GOG:-0}"; then
  echo "  • gog:      run gog auth on the host, then: make sync-gog-config && make restart-dev"
fi
if ! truthy "${SKIP_GOG:-0}"; then
  echo "  • Verify gog in container: make verify-gog"
fi
if places_enabled && ! truthy "${SKIP_GOPLACES:-0}"; then
  echo "  • Places: share Telegram location, then ask for nearby vegan restaurants"
  echo "  • Verify goplaces: make verify-goplaces"
fi
