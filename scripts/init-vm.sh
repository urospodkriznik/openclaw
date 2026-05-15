#!/usr/bin/env bash
# Entry point for `make init-vm`: scaffold .env, preflight, then scripts/setup-vm.sh
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
│  OpenClaw GCP VM setup — step 1 of 2                         │
└──────────────────────────────────────────────────────────────┘

Created .env from .env.example.

Edit .env for this VM (typical production values):
EOF
  describe_required_env_bullets vm
  cat <<'EOF'

Recommended on GCP: USE_GSM_SECRETS=true and GSM_* secret names (not raw tokens in .env).

Set LLM_PROVIDER to google (default) or openai — only the matching GSM secret or API key is required.

Host packages (once, with sudo):
  sudo ./scripts/setup-server.sh
  sudo ./scripts/install-docker.sh
Or on the next init-vm: INSTALL_HOST_DEPS=1 make init-vm

When .env is ready, run:

  make init-vm

EOF
}

print_missing_banner() {
  cat <<'EOF'

┌──────────────────────────────────────────────────────────────┐
│  OpenClaw GCP VM setup — finish .env / Docker, then retry    │
└──────────────────────────────────────────────────────────────┘

EOF
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    collect_missing_env_vars vm
    if ((${#MISSING_ENV_VARS[@]} > 0)); then
      echo "Still need values in .env:"
      printf '  • %s\n' "${MISSING_ENV_VARS[@]}"
      echo ""
      echo "Then run: make init-vm"
    fi
  fi
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "init-vm: use make init on macOS. init-vm is for a Linux GCP VM." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  cp .env.example "$ENV_FILE"
  print_scaffold_banner
  exit 0
fi

if ! ./scripts/setup-vm.sh --preflight-only; then
  print_missing_banner
  exit 0
fi

exec ./scripts/setup-vm.sh
