#!/usr/bin/env bash
# Validate .env, autonomy flags, and required paths before deploy / compose up.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=lib/required-env.sh
source "$ROOT_DIR/scripts/lib/required-env.sh"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

err() { echo "validate-env: $*" >&2; exit 1; }

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

if truthy "${TRUSTED_HEADLESS_EXEC:-false}"; then
  if truthy "${FULL_AUTONOMY:-false}"; then
    err "TRUSTED_HEADLESS_EXEC and FULL_AUTONOMY cannot both be true (use only one)."
  fi
  if truthy "${DEMO_MODE:-false}"; then
    err "TRUSTED_HEADLESS_EXEC cannot be used with DEMO_MODE."
  fi
  if ! truthy "${I_ACCEPT_HEADLESS_EXEC_RISK:-}"; then
    err "TRUSTED_HEADLESS_EXEC=true requires I_ACCEPT_HEADLESS_EXEC_RISK=1 (headless gateway: exec approvals cannot be answered without Control UI unless policy is opened)."
  fi
fi

if truthy "${DEMO_MODE:-false}"; then
  if truthy "${ENABLE_GMAIL_HOOKS:-false}"; then
    err "DEMO_MODE requires ENABLE_GMAIL_HOOKS=false."
  fi
fi

: "${GOOGLE_CLOUD_PROJECT:?Set GOOGLE_CLOUD_PROJECT in .env}"
: "${GOOGLE_CLOUD_LOCATION:?Set GOOGLE_CLOUD_LOCATION in .env}"
: "${GEMINI_MODEL:=gemini-3-flash-preview}"
: "${OPENAI_MODEL:=gpt-4.1-mini}"

if [[ "${VALIDATION_LEVEL:-full}" == "full" ]]; then
  case "$(llm_provider_lc)" in
    openai)
      if [[ -z "${OPENAI_API_KEY:-}" ]] && ! truthy "${USE_GSM_SECRETS:-false}"; then
        err "LLM_PROVIDER=openai requires OPENAI_API_KEY in .env (or USE_GSM_SECRETS=true with secrets that supply it)."
      fi
      ;;
    google | gemini)
      if [[ -z "${GEMINI_API_KEY:-}" ]] && ! truthy "${USE_GSM_SECRETS:-false}"; then
        err "LLM_PROVIDER=google requires GEMINI_API_KEY in .env (or USE_GSM_SECRETS=true with GSM_GEMINI_API_KEY_SECRET)."
      fi
      ;;
    *)
      err "LLM_PROVIDER must be google or openai (got: ${LLM_PROVIDER:-})"
      ;;
  esac
fi

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-./.openclaw-config}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./workspace}"
mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR" "${ROOT_DIR}/secrets"

if [[ "${VALIDATION_LEVEL:-full}" == "full" ]] && [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] && ! truthy "${USE_GSM_SECRETS:-false}"; then
  err "TELEGRAM_BOT_TOKEN is empty (or set USE_GSM_SECRETS=true to source it from Google Secret Manager)."
fi

if truthy "${ENABLE_GMAIL_HOOKS:-false}"; then
  if [[ "${OPENCLAW_SKIP_GMAIL_WATCHER:-1}" == "1" ]]; then
    err "ENABLE_GMAIL_HOOKS=true requires OPENCLAW_SKIP_GMAIL_WATCHER=0 (set it in .env, or run ./scripts/align-gmail-watcher-env.sh before validate; deploy does this automatically)."
  fi
fi

if truthy "${USE_GSM_SECRETS:-false}"; then
  : "${GSM_PROJECT_ID:=${GOOGLE_CLOUD_PROJECT}}"
  : "${GSM_TELEGRAM_BOT_TOKEN_SECRET:?Set GSM_TELEGRAM_BOT_TOKEN_SECRET when USE_GSM_SECRETS=true}"
fi

echo "validate-env: OK (GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT location=$GOOGLE_CLOUD_LOCATION LLM_PROVIDER=${LLM_PROVIDER:-google} gemini_model=$GEMINI_MODEL openai_model=$OPENAI_MODEL)"
