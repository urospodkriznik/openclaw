#!/usr/bin/env bash
# One-shot Google Places (goplaces) on a Linux VM after the gateway is up.
# Installs Linux goplaces, verifies API key + binary in containers, installs ClawHub skill.
#
# Prereqs:
#   - Places API (New) enabled on GOOGLE_CLOUD_PROJECT (places.googleapis.com)
#   - GOOGLE_PLACES_API_KEY in .env, or GSM_GOOGLE_PLACES_API_KEY_SECRET + fetch-secrets-gsm.sh
#
# Usage: make setup-places
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE=(./scripts/docker-compose.sh)

step() { echo ""; echo "==> $*"; }

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "setup-places-vm: use on the Linux VM (local Mac: make install-goplaces-linux && make restart-dev)." >&2
  exit 1
fi

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
  if [[ -f "$ROOT_DIR/.env.generated" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ROOT_DIR/.env.generated"
    set +a
  fi
}

load_env

places_configured() {
  [[ -n "${GOOGLE_PLACES_API_KEY:-}" ]] || [[ -n "${GSM_GOOGLE_PLACES_API_KEY_SECRET:-}" ]]
}

if ! places_configured; then
  echo "setup-places-vm: configure Places first:" >&2
  echo "  • Local: GOOGLE_PLACES_API_KEY=AIza… in .env" >&2
  echo "  • GCP:   GSM_GOOGLE_PLACES_API_KEY_SECRET=<Secret Manager secret id> in .env" >&2
  echo "         (the secret's NAME in GCP — can match this env var name if you created it that way)" >&2
  exit 1
fi

detect_goplaces_arch() {
  if [[ -n "${GOPLACES_LINUX_ARCH:-}" ]]; then
    return 0
  fi
  case "$(uname -m)" in
    arm64 | aarch64) export GOPLACES_LINUX_ARCH=arm64 ;;
    *) export GOPLACES_LINUX_ARCH=amd64 ;;
  esac
}

step "Fetch GSM secrets (no-op when USE_GSM_SECRETS=false)"
./scripts/fetch-secrets-gsm.sh
load_env

if [[ -z "${GOOGLE_PLACES_API_KEY:-}" ]]; then
  echo "setup-places-vm: still no GOOGLE_PLACES_API_KEY after fetch-secrets-gsm.sh" >&2
  echo "  Check: USE_GSM_SECRETS=true, secret exists, VM SA has Secret Accessor, secret has a version." >&2
  echo "  Test:  gcloud secrets versions access latest --secret=\"\$GSM_GOOGLE_PLACES_API_KEY_SECRET\" --project=\"\$GOOGLE_CLOUD_PROJECT\"" >&2
  exit 1
fi

step "Install Linux goplaces for Docker"
detect_goplaces_arch
./scripts/install-goplaces-linux-for-docker.sh

step "Re-own mounts and recreate gateway (goplaces overlay + env)"
./scripts/reown-openclaw-mounts.sh --host
./scripts/reown-openclaw-mounts.sh --container
"${COMPOSE[@]}" up -d --force-recreate
sleep 15

step "Verify goplaces binary and API key in containers"
./scripts/verify-goplaces-in-container.sh

step "Install goplaces skill (ClawHub)"
if ! "${COMPOSE[@]}" run -T --rm openclaw-cli skills install goplaces; then
  echo "setup-places-vm: skill install failed — retry when gateway is healthy:" >&2
  echo "  ${COMPOSE[*]} run -T --rm openclaw-cli skills install goplaces" >&2
  exit 1
fi

step "Health check"
./scripts/healthcheck.sh

echo ""
echo "setup-places-vm: done."
echo "  • Telegram: /new → share Location → ask for nearby vegan restaurants (example)."
echo "  • Smoke:    ${COMPOSE[*]} run -T --rm --entrypoint /bin/sh openclaw-cli -c 'goplaces search \"vegan\" --lat 46.05 --lng 14.51 --radius-m 2000 --open-now --limit 3'"
echo "  • Docs:     docs/GOOGLE_INTEGRATIONS.md"
