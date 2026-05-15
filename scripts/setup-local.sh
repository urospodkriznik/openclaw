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
#   SKIP_TELEGRAM=1         Skip `channels add`
#   SKIP_PULL=1             Skip `docker compose pull`
#   SETUP_NO_RECREATE=1   Use `up -d` instead of `--force-recreate`
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_DEV=(./scripts/docker-compose.sh -f docker-compose.dev.yml)

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

truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

llm_provider_lc() {
  echo "${LLM_PROVIDER:-google}" | tr '[:upper:]' '[:lower:]'
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "setup-local: missing $ENV_FILE" >&2
    echo "  Run: cp .env.example .env" >&2
    echo "  Then set GOOGLE_CLOUD_*, LLM keys, and TELEGRAM_BOT_TOKEN (see .env.example)." >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

env_placeholder_or_empty() {
  local v="${1:-}"
  [[ -z "$v" ]] && return 0
  case "$v" in
    changeme | CHANGE_ME | your-* | YOUR_* | placeholder*) return 0 ;;
  esac
  return 1
}

check_env_filled() {
  local missing=()
  env_placeholder_or_empty "${GOOGLE_CLOUD_PROJECT:-}" && missing+=(GOOGLE_CLOUD_PROJECT)
  env_placeholder_or_empty "${GOOGLE_CLOUD_LOCATION:-}" && missing+=(GOOGLE_CLOUD_LOCATION)

  case "$(llm_provider_lc)" in
    openai)
      if ! truthy "${USE_GSM_SECRETS:-false}" && env_placeholder_or_empty "${OPENAI_API_KEY:-}"; then
        missing+=(OPENAI_API_KEY)
      fi
      ;;
    google | gemini)
      if ! truthy "${USE_GSM_SECRETS:-false}" && env_placeholder_or_empty "${GEMINI_API_KEY:-}"; then
        missing+=(GEMINI_API_KEY)
      fi
      ;;
    *)
      missing+=("LLM_PROVIDER (must be google or openai)")
      ;;
  esac

  if ! truthy "${USE_GSM_SECRETS:-false}" && env_placeholder_or_empty "${TELEGRAM_BOT_TOKEN:-}"; then
    missing+=(TELEGRAM_BOT_TOKEN)
  fi

  if ((${#missing[@]} > 0)); then
    echo "setup-local: edit $ENV_FILE and set:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
  fi
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
  detect_gog_arch
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
