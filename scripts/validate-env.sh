#!/usr/bin/env bash
# Validate .env, autonomy flags, and required paths before deploy / compose up.
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

err() { echo "validate-env: $*" >&2; exit 1; }

truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

if truthy "${DEMO_MODE:-false}" && truthy "${FULL_AUTONOMY:-false}"; then
  err "DEMO_MODE and FULL_AUTONOMY cannot both be true."
fi

if truthy "${FULL_AUTONOMY:-false}"; then
  if truthy "${DEMO_MODE:-false}"; then
    err "FULL_AUTONOMY cannot be used with DEMO_MODE."
  fi
  if ! truthy "${I_ACCEPT_FULL_AUTONOMY_RISK:-}"; then
    err "FULL_AUTONOMY=true requires I_ACCEPT_FULL_AUTONOMY_RISK=1 in .env (you accept host/exec risk)."
  fi
  if truthy "${SAFE_MODE:-true}"; then
    echo "Warning: FULL_AUTONOMY with SAFE_MODE=true is contradictory; set SAFE_MODE=false for YOLO-style exec." >&2
  fi
fi

if truthy "${DEMO_MODE:-false}"; then
  if truthy "${ENABLE_GMAIL_HOOKS:-false}"; then
    err "DEMO_MODE requires ENABLE_GMAIL_HOOKS=false."
  fi
fi

: "${GOOGLE_CLOUD_PROJECT:?Set GOOGLE_CLOUD_PROJECT in .env}"
: "${GOOGLE_CLOUD_LOCATION:?Set GOOGLE_CLOUD_LOCATION in .env}"
: "${VERTEX_MODEL:?Set VERTEX_MODEL in .env}"

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-./.openclaw-config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./workspace}"
mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR" "${ROOT_DIR}/secrets"

if [[ "${VALIDATION_LEVEL:-full}" == "full" ]] && [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] && ! truthy "${USE_GSM_SECRETS:-false}"; then
  err "TELEGRAM_BOT_TOKEN is empty (or set USE_GSM_SECRETS=true to source it from Google Secret Manager)."
fi

if truthy "${ENABLE_GMAIL_HOOKS:-false}"; then
  if [[ "${OPENCLAW_SKIP_GMAIL_WATCHER:-1}" == "1" ]]; then
    err "ENABLE_GMAIL_HOOKS=true requires OPENCLAW_SKIP_GMAIL_WATCHER=0"
  fi
fi

if truthy "${USE_GSM_SECRETS:-false}"; then
  : "${GSM_PROJECT_ID:=${GOOGLE_CLOUD_PROJECT}}"
  : "${GSM_TELEGRAM_BOT_TOKEN_SECRET:?Set GSM_TELEGRAM_BOT_TOKEN_SECRET when USE_GSM_SECRETS=true}"
fi

echo "validate-env: OK (GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT location=$GOOGLE_CLOUD_LOCATION)"
