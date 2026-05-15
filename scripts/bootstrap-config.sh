#!/usr/bin/env bash
# Seed OpenClaw config dir: openclaw.json + exec-approvals.json from autonomy mode.
# Run after .env is filled. Idempotent: refreshes policy files when modes change.
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
mkdir -p "$CONFIG_DIR"

if [[ ! -w "$CONFIG_DIR" ]]; then
  echo "bootstrap-config: error: $CONFIG_DIR is not writable by $(id -un) (common after Docker created it as UID 1000)." >&2
  echo "Fix (same order as deploy): ./scripts/reown-openclaw-mounts.sh --host" >&2
  echo "Then: ./scripts/bootstrap-config.sh   (needs passwordless sudo for chown; see docs/TROUBLESHOOTING.md)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "bootstrap-config: install jq (e.g. apt install jq / brew install jq)" >&2
  exit 1
fi

truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

llm_provider_lc() {
  echo "${LLM_PROVIDER:-google}" | tr '[:upper:]' '[:lower:]'
}

resolve_primary_model() {
  local p
  p="$(llm_provider_lc)"
  case "$p" in
    openai)
      printf 'openai/%s' "${OPENAI_MODEL:-gpt-4.1-mini}"
      ;;
    google | gemini)
      printf 'google/%s' "${GEMINI_MODEL:-gemini-3-flash-preview}"
      ;;
    *)
      echo "bootstrap-config: LLM_PROVIDER must be google or openai (got: ${LLM_PROVIDER:-})" >&2
      exit 1
      ;;
  esac
}

PRIMARY_MODEL="$(resolve_primary_model)"

# openai/gpt-* on recent images routes via Codex unless models.providers.openai is complete.
# A bare models.providers.openai.agentRuntime object crashes the gateway (missing baseUrl/models).
# Use `openclaw doctor --fix` after the stack is healthy — see docs/TROUBLESHOOTING.md.
openai_post_bootstrap_hint() {
  [[ "$PRIMARY_MODEL" == openai/* ]] || return 0
  echo "OpenAI: if Telegram shows 'codex is not registered', run (stack must be up):"
  echo "  ./scripts/docker-compose.sh run -T --rm openclaw-cli doctor --fix"
  echo "  make restart-dev"
  echo "  Then /new in Telegram. Or set OPENAI_MODEL=gpt-4.1-mini and re-run bootstrap."
}

# Host .env token for compose interpolation
if [[ -f "$ENV_FILE" ]] && grep -qE '^OPENCLAW_GATEWAY_TOKEN=.+' "$ENV_FILE"; then
  line="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=.+' "$ENV_FILE" | tail -n1)"
  export OPENCLAW_GATEWAY_TOKEN="${line#OPENCLAW_GATEWAY_TOKEN=}"
fi

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]] && [[ -f "$ENV_FILE" ]]; then
  TOKEN="$(openssl rand -hex 24)"
  {
    echo ""
    echo "# Added by bootstrap-config.sh"
    echo "OPENCLAW_GATEWAY_TOKEN=$TOKEN"
  } >>"$ENV_FILE"
  export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
  echo "Generated OPENCLAW_GATEWAY_TOKEN and appended to .env"
elif [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  echo "No .env file; set OPENCLAW_GATEWAY_TOKEN manually." >&2
  exit 1
fi

# Gateway-local secrets (OpenClaw also reads mounted home)
umask 077
cat >"${CONFIG_DIR}/.env" <<EOF
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
EOF
umask 022

EXEC_FILE="${CONFIG_DIR}/exec-approvals.json"
# Headless VM (Telegram-only): SAFE_MODE ask=on-miss needs Control UI / companion to approve;
# without it, prompts time out and shell/help commands fail. TRUSTED_HEADLESS_EXEC opens gateway
# exec the same way as FULL_AUTONOMY for tools only — still set I_ACCEPT_HEADLESS_EXEC_RISK=1.
if truthy "${FULL_AUTONOMY:-false}" && truthy "${I_ACCEPT_FULL_AUTONOMY_RISK:-}"; then
  cat >"$EXEC_FILE" <<'EOF'
{
  "version": 1,
  "defaults": {
    "security": "full",
    "ask": "off",
    "askFallback": "full",
    "autoAllowSkills": false
  }
}
EOF
elif truthy "${TRUSTED_HEADLESS_EXEC:-false}" && truthy "${I_ACCEPT_HEADLESS_EXEC_RISK:-}"; then
  cat >"$EXEC_FILE" <<'EOF'
{
  "version": 1,
  "defaults": {
    "security": "full",
    "ask": "off",
    "askFallback": "full",
    "autoAllowSkills": false
  }
}
EOF
elif truthy "${DEMO_MODE:-false}"; then
  # Portfolio demo: conservative exec, strong prompts; no Gmail hooks (enforced via env/docs).
  cat >"$EXEC_FILE" <<'EOF'
{
  "version": 1,
  "defaults": {
    "security": "allowlist",
    "ask": "always",
    "askFallback": "deny",
    "autoAllowSkills": false
  }
}
EOF
else
  # SAFE_MODE default
  cat >"$EXEC_FILE" <<'EOF'
{
  "version": 1,
  "defaults": {
    "security": "allowlist",
    "ask": "on-miss",
    "askFallback": "deny",
    "autoAllowSkills": false
  }
}
EOF
fi

OPENCLAW_JSON="${CONFIG_DIR}/openclaw.json"
TOOLS_SECURITY="allowlist"
TOOLS_ASK="on-miss"
if truthy "${FULL_AUTONOMY:-false}" && truthy "${I_ACCEPT_FULL_AUTONOMY_RISK:-}"; then
  TOOLS_SECURITY="full"
  TOOLS_ASK="off"
elif truthy "${TRUSTED_HEADLESS_EXEC:-false}" && truthy "${I_ACCEPT_HEADLESS_EXEC_RISK:-}"; then
  TOOLS_SECURITY="full"
  TOOLS_ASK="off"
elif truthy "${DEMO_MODE:-false}"; then
  TOOLS_SECURITY="allowlist"
  TOOLS_ASK="always"
fi

# Minimal JSON (OpenClaw accepts JSON5; we emit strict JSON for tooling).
# - commands.text: Telegram often omits bot_command entities; text parsing fixes /new, /reset, etc.
# - session.dmScope main: single-user DMs share one session (continuity across messages).
# - startupContext.applyOn: only "reset" avoids re-injecting the first-turn startup prelude on every turn
#   when the runtime treats a turn as "new" (fixes repeated "fresh workspace" replies in Telegram).
# If openclaw.json already exists (Telegram channels, plugins, etc.), merge only model.primary + tools.exec.
write_openclaw_json() {
  local tmp="${OPENCLAW_JSON}.tmp"
  if [[ -f "$OPENCLAW_JSON" ]] && jq -e 'type == "object"' "$OPENCLAW_JSON" >/dev/null 2>&1; then
    if jq --arg primary "$PRIMARY_MODEL" \
      --arg sec "$TOOLS_SECURITY" \
      --arg ask "$TOOLS_ASK" \
      '
      .agents //= {}
      | .agents.defaults //= {}
      | .agents.defaults.model //= {}
      | .agents.defaults.model.primary = $primary
      | .tools //= {}
      | .tools.exec = { host: "gateway", security: $sec, ask: $ask }
      ' "$OPENCLAW_JSON" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$OPENCLAW_JSON"
      return 0
    fi
    rm -f "$tmp"
  fi
  jq -n \
    --arg primary "$PRIMARY_MODEL" \
    --arg sec "$TOOLS_SECURITY" \
    --arg ask "$TOOLS_ASK" \
    '{
    gateway: { mode: "local", bind: "lan" },
    commands: { text: true, native: "auto", nativeSkills: "auto" },
    session: { dmScope: "main" },
    agents: {
      defaults: {
        model: { primary: $primary },
        startupContext: { enabled: true, applyOn: ["reset"] }
      }
    },
    tools: { exec: { host: "gateway", security: $sec, ask: $ask } }
  }' >"$tmp"
  mv "$tmp" "$OPENCLAW_JSON"
}

write_openclaw_json

echo "bootstrap-config: wrote $OPENCLAW_JSON and $EXEC_FILE (primary=$PRIMARY_MODEL)"
openai_post_bootstrap_hint
if truthy "${TRUSTED_HEADLESS_EXEC:-false}" && truthy "${I_ACCEPT_HEADLESS_EXEC_RISK:-}" && ! truthy "${FULL_AUTONOMY:-false}"; then
  echo "Headless exec: tools.exec + exec-approvals use security=full ask=off (no Control UI). Gmail/Calendar/Drive need skills + OAuth per docs/GOOGLE_INTEGRATIONS.md."
fi
echo "Next (local): make init   — or manually: channels add + make restart-dev (see README)"
case "$(llm_provider_lc)" in
  openai)
    echo "OpenAI: set OPENAI_API_KEY in .env. Verify: ./scripts/docker-compose.sh run -T --rm openclaw-cli models list --provider openai"
    ;;
  *)
    echo "Gemini: set GEMINI_API_KEY in .env (or GSM_GEMINI_API_KEY_SECRET + fetch-secrets-gsm.sh). Verify: ./scripts/docker-compose.sh run -T --rm openclaw-cli models list --provider google"
    ;;
esac
