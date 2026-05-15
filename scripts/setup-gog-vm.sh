#!/usr/bin/env bash
# One-shot gog on a Linux VM after the gateway is up (SKIP_GOG=1 init-vm or post-deploy).
# Installs Linux gog, syncs host ~/.config/gogcli → staging → container volume, restarts, verifies.
#
# Prereqs: .env with GOG_KEYRING_BACKEND=file, GOG_KEYRING_PASSWORD, optional GOG_ACCOUNT.
# Host:    gog auth credentials … && gog auth add … (use --manual on headless VMs).
#
# Usage: make setup-gog
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE=(./scripts/docker-compose.sh)

step() { echo ""; echo "==> $*"; }

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "setup-gog-vm: use on the Linux VM (or run sync/push steps from docs/GOOGLE_INTEGRATIONS.md on Mac)." >&2
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

missing=()
if [[ -z "${GOG_KEYRING_BACKEND:-}" ]]; then
  missing+=(GOG_KEYRING_BACKEND)
fi
if [[ -z "${GOG_KEYRING_PASSWORD:-}" ]]; then
  missing+=(GOG_KEYRING_PASSWORD)
fi
if ((${#missing[@]} > 0)); then
  echo "setup-gog-vm: add to .env (see .env.example):" >&2
  printf '  • %s\n' "${missing[@]}" >&2
  exit 1
fi

host_gogcli_source() {
  if [[ -n "${GOGCLI_SOURCE_DIR:-}" && -f "${GOGCLI_SOURCE_DIR}/credentials.json" ]]; then
    printf '%s' "${GOGCLI_SOURCE_DIR}"
    return 0
  fi
  if [[ -f "${HOME}/.config/gogcli/credentials.json" ]]; then
    printf '%s' "${HOME}/.config/gogcli"
    return 0
  fi
  return 1
}

print_auth_help() {
  cat <<'EOF'

No host gogcli OAuth state yet (need credentials.json under ~/.config/gogcli).

On this VM (headless — use --manual in your laptop browser):

  set -a && source .env && set +a
  gog auth credentials /path/to/client_secret.json
  gog auth add you@gmail.com --services gmail,calendar,drive,docs,sheets --manual

Or authorize on your Mac with the same GOG_* vars in .env, then copy/sync from the VM:

  make sync-gog-config && make setup-gog

Docs: docs/GOOGLE_INTEGRATIONS.md

EOF
}

step "Install Linux gog for Docker (ELF bind-mount)"
./scripts/install-gog-linux-for-docker.sh

if ! src="$(host_gogcli_source)"; then
  print_auth_help
  exit 1
fi
echo "Host gogcli source: $src"

step "Sync gogcli into OPENCLAW_GOGCLI_CONFIG_DIR (host staging)"
./scripts/reown-openclaw-mounts.sh --host
./scripts/sync-gog-cli-config.sh

step "Re-own mounts for container UID 1000"
./scripts/reown-openclaw-mounts.sh --container

step "Recreate gateway and push gogcli into the named volume"
"${COMPOSE[@]}" up -d --force-recreate
sleep 15
./scripts/push-gogcli-to-gateway.sh

step "Verify gog binary in containers"
./scripts/verify-gog-in-container.sh

step "gog auth doctor (container)"
if ! "${COMPOSE[@]}" run -T --rm --entrypoint /bin/sh openclaw-cli \
  -c 'command -v gog >/dev/null && gog auth doctor --check'; then
  echo "setup-gog-vm: doctor check failed — see docs/TROUBLESHOOTING.md (gog overlay, keyring password)" >&2
  exit 1
fi

echo ""
echo "setup-gog-vm: done. Message the bot and try a Workspace command (Gmail/Calendar)."
echo "  Logs: make logs"
