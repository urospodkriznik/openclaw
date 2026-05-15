# Shared helpers for local / VM init, setup, and validate (source, do not execute).
# shellcheck shell=bash

truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

llm_provider_lc() {
  echo "${LLM_PROVIDER:-google}" | tr '[:upper:]' '[:lower:]'
}

env_placeholder_or_empty() {
  local v="${1:-}"
  [[ -z "$v" ]] && return 0
  # Exact placeholders from .env.example only (do not use your-* — it false-positives on your-gcp-project-id).
  case "$v" in
    changeme | CHANGE_ME | REPLACE_ME | your-gcp-project-id | placeholder-for-ci) return 0 ;;
  esac
  case "$v" in
    placeholder* | YOUR_* | CHANGE_ME_*) return 0 ;;
  esac
  return 1
}

# Sets MISSING_ENV_VARS array. target: local | vm (vm allows GSM-only secrets).
collect_missing_env_vars() {
  local target="${1:-local}"
  MISSING_ENV_VARS=()
  # Use `if` — not `cmd && …`. env_placeholder_or_empty returns 1 for valid values, which trips set -e with &&.
  if env_placeholder_or_empty "${GOOGLE_CLOUD_PROJECT:-}"; then
    MISSING_ENV_VARS+=(GOOGLE_CLOUD_PROJECT)
  fi
  if env_placeholder_or_empty "${GOOGLE_CLOUD_LOCATION:-}"; then
    MISSING_ENV_VARS+=(GOOGLE_CLOUD_LOCATION)
  fi

  if truthy "${USE_GSM_SECRETS:-false}"; then
    if env_placeholder_or_empty "${GSM_TELEGRAM_BOT_TOKEN_SECRET:-}"; then
      MISSING_ENV_VARS+=(GSM_TELEGRAM_BOT_TOKEN_SECRET)
    fi
    case "$(llm_provider_lc)" in
      openai)
        if env_placeholder_or_empty "${GSM_OPENAI_API_KEY_SECRET:-}"; then
          MISSING_ENV_VARS+=(GSM_OPENAI_API_KEY_SECRET)
        fi
        ;;
      google | gemini)
        if env_placeholder_or_empty "${GSM_GEMINI_API_KEY_SECRET:-}"; then
          MISSING_ENV_VARS+=(GSM_GEMINI_API_KEY_SECRET)
        fi
        ;;
      *)
        MISSING_ENV_VARS+=("LLM_PROVIDER (must be google or openai)")
        ;;
    esac
    return 0
  fi

  case "$(llm_provider_lc)" in
    openai)
      if env_placeholder_or_empty "${OPENAI_API_KEY:-}"; then
        MISSING_ENV_VARS+=(OPENAI_API_KEY)
      fi
      ;;
    google | gemini)
      if env_placeholder_or_empty "${GEMINI_API_KEY:-}"; then
        MISSING_ENV_VARS+=(GEMINI_API_KEY)
      fi
      ;;
    *)
      MISSING_ENV_VARS+=("LLM_PROVIDER (must be google or openai)")
      ;;
  esac

  if env_placeholder_or_empty "${TELEGRAM_BOT_TOKEN:-}"; then
    MISSING_ENV_VARS+=(TELEGRAM_BOT_TOKEN)
  fi
}

llm_api_key_label() {
  if truthy "${USE_GSM_SECRETS:-false}"; then
    case "$(llm_provider_lc)" in
      openai) printf '%s' "GSM_OPENAI_API_KEY_SECRET (LLM_PROVIDER=openai)" ;;
      google | gemini) printf '%s' "GSM_GEMINI_API_KEY_SECRET (LLM_PROVIDER=google)" ;;
      *) printf '%s' "GSM LLM secret for LLM_PROVIDER" ;;
    esac
    return 0
  fi
  case "$(llm_provider_lc)" in
    openai) printf '%s' "OPENAI_API_KEY (LLM_PROVIDER=openai)" ;;
    google | gemini) printf '%s' "GEMINI_API_KEY (LLM_PROVIDER=google)" ;;
    *) printf '%s' "LLM API key for LLM_PROVIDER" ;;
  esac
}

describe_required_env_bullets() {
  local target="${1:-local}"
  echo "  • GOOGLE_CLOUD_PROJECT"
  echo "  • GOOGLE_CLOUD_LOCATION"
  if truthy "${USE_GSM_SECRETS:-false}"; then
    echo "  • USE_GSM_SECRETS=true"
    echo "  • GSM_TELEGRAM_BOT_TOKEN_SECRET"
    echo "  • $(llm_api_key_label)"
    if [[ "$target" == "vm" ]]; then
      echo "  • VM service account: Secret Manager Secret Accessor (+ gcloud on host for fetch-secrets-gsm.sh)"
    fi
  else
    echo "  • TELEGRAM_BOT_TOKEN"
    echo "  • $(llm_api_key_label)"
    if [[ "$target" == "vm" ]]; then
      echo "  • (optional on VM) USE_GSM_SECRETS=true + GSM_* secret names instead of raw tokens in .env"
    fi
  fi
}
