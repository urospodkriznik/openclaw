#!/usr/bin/env bash
# Entry point for `make init`: scaffold .env on first run, preflight secrets, then full setup.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

# shellcheck source=lib/required-env.sh
source "$ROOT_DIR/scripts/lib/required-env.sh"

load_env_if_present() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

print_scaffold_banner() {
  load_env_if_present
  cat <<'EOF'

┌──────────────────────────────────────────────────────────────┐
│  OpenClaw local setup — step 1 of 2                          │
└──────────────────────────────────────────────────────────────┘

Created .env from .env.example.

Edit .env and set at least:
EOF
  describe_required_env_bullets local
  cat <<'EOF'

Set LLM_PROVIDER to google (default) or openai — only the matching API key is required.

Optional: GOG_* and run `gog auth` on the host for Google Workspace.

When .env is ready, run:

  make init

EOF
}

print_missing_banner() {
  cat <<'EOF'

┌──────────────────────────────────────────────────────────────┐
│  OpenClaw local setup — finish .env, then run make init again │
└──────────────────────────────────────────────────────────────┘

EOF
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    collect_missing_env_vars local
    if ((${#MISSING_ENV_VARS[@]} > 0)); then
      echo "Still need values in .env:"
      printf '  • %s\n' "${MISSING_ENV_VARS[@]}"
      echo ""
      echo "Then run: make init"
    fi
  fi
}

if [[ ! -f "$ENV_FILE" ]]; then
  cp .env.example "$ENV_FILE"
  print_scaffold_banner
  exit 0
fi

if ! ./scripts/setup-local.sh --preflight-only; then
  print_missing_banner
  exit 0
fi

exec ./scripts/setup-local.sh
