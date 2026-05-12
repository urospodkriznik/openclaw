#!/usr/bin/env bash
# Fetch runtime secrets from Google Secret Manager into .env.generated.
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

truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

if ! truthy "${USE_GSM_SECRETS:-false}"; then
  rm -f "$ROOT_DIR/.env.generated"
  echo "fetch-secrets-gsm: USE_GSM_SECRETS=false, removed .env.generated"
  exit 0
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "fetch-secrets-gsm: gcloud CLI is required when USE_GSM_SECRETS=true" >&2
  exit 1
fi

PROJECT="${GSM_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
if [[ -z "$PROJECT" ]]; then
  echo "fetch-secrets-gsm: set GSM_PROJECT_ID or GOOGLE_CLOUD_PROJECT" >&2
  exit 1
fi

TELEGRAM_SECRET="${GSM_TELEGRAM_BOT_TOKEN_SECRET:-}"
OPENAI_SECRET="${GSM_OPENAI_API_KEY_SECRET:-}"
GEMINI_SECRET="${GSM_GEMINI_API_KEY_SECRET:-}"
if [[ -z "$TELEGRAM_SECRET" ]]; then
  echo "fetch-secrets-gsm: set GSM_TELEGRAM_BOT_TOKEN_SECRET" >&2
  exit 1
fi

telegram_value="$(gcloud secrets versions access latest --secret="$TELEGRAM_SECRET" --project="$PROJECT")"
openai_value=""
if [[ -n "$OPENAI_SECRET" ]]; then
  openai_value="$(gcloud secrets versions access latest --secret="$OPENAI_SECRET" --project="$PROJECT" 2>/dev/null || true)"
fi
gemini_value=""
if [[ -n "$GEMINI_SECRET" ]]; then
  gemini_value="$(gcloud secrets versions access latest --secret="$GEMINI_SECRET" --project="$PROJECT" 2>/dev/null || true)"
fi

umask 077
{
  printf 'TELEGRAM_BOT_TOKEN=%s\n' "$telegram_value"
  if [[ -n "$openai_value" ]]; then
    printf 'OPENAI_API_KEY=%s\n' "$openai_value"
  fi
  if [[ -n "$gemini_value" ]]; then
    printf 'GEMINI_API_KEY=%s\n' "$gemini_value"
  fi
} > "$ROOT_DIR/.env.generated"
umask 022

echo "fetch-secrets-gsm: wrote .env.generated from Secret Manager project $PROJECT"
