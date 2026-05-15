#!/usr/bin/env bash
# Run docker compose with docker-compose.yml plus docker-compose.gog.yml when the
# host gog binary is available (so openclaw-gateway and openclaw-cli both see /usr/local/bin/gog
# inside the container). Mount source path is OPENCLAW_GOG_HOST_PATH (exported when auto-detected).
# Leading "-f <file>" pairs are forwarded after the baseline files (for dev overrides).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE" 2>/dev/null || true
  set +a
fi

# Resolve host path to a gog **Linux ELF** binary for bind-mount into the container (the
# image OS is Linux). macOS Homebrew gog is Mach-O and will not run — use
# ./scripts/install-gog-linux-for-docker.sh to populate .openclaw-host-bin/gog.
gog_is_linux_elf() {
  local magic
  [[ -f "$1" ]] || return 1
  if command -v file >/dev/null 2>&1; then
    file -b "$1" 2>/dev/null | grep -qi 'ELF' && return 0
  fi
  # Minimal VMs often lack the `file` package; read ELF magic (0x7f 'ELF').
  magic="$(head -c 4 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' || true)"
  [[ "$magic" == "7f454c46" ]]
}

pick_gog_host_binary() {
  local p
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    if gog_is_linux_elf "$p"; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# Resolve host gog binary: explicit OPENCLAW_GOG_HOST_PATH if it is a Linux ELF file; otherwise
# try .openclaw-host-bin/gog (from install-gog-linux-for-docker.sh), then /usr/local/bin/gog,
# then /opt/homebrew/bin/gog (last is almost always Mach-O on Mac — skipped unless ELF).
GOG_PATH=""
if [[ -n "${OPENCLAW_GOG_HOST_PATH:-}" ]]; then
  if gog_is_linux_elf "${OPENCLAW_GOG_HOST_PATH}"; then
    GOG_PATH="${OPENCLAW_GOG_HOST_PATH}"
  else
    echo "docker-compose.sh: OPENCLAW_GOG_HOST_PATH is not a Linux ELF binary: ${OPENCLAW_GOG_HOST_PATH}" >&2
    echo "docker-compose.sh: (macOS host gog cannot run in the container — run ./scripts/install-gog-linux-for-docker.sh)" >&2
  fi
else
  if cand="$(pick_gog_host_binary "${ROOT_DIR}/.openclaw-host-bin/gog" /usr/local/bin/gog /opt/homebrew/bin/gog)"; then
    GOG_PATH="$cand"
  fi
fi

if [[ -z "$GOG_PATH" ]] && { [[ -f "${ROOT_DIR}/.openclaw-host-bin/gog" ]] || [[ -f /opt/homebrew/bin/gog ]] || [[ -f /usr/local/bin/gog ]]; }; then
  echo "docker-compose.sh: skipping gog overlay — no Linux ELF gog found (containers are Linux)." >&2
  echo "docker-compose.sh: On a Mac: ./scripts/install-gog-linux-for-docker.sh  then re-run compose." >&2
fi

compose_files=( -f docker-compose.yml )
if [[ -n "$GOG_PATH" ]]; then
  export OPENCLAW_GOG_HOST_PATH="$GOG_PATH"
  compose_files+=( -f docker-compose.gog.yml )
fi

extra=()
while [[ "${1:-}" == "-f" && -n "${2:-}" ]]; do
  extra+=( -f "$2" )
  shift 2
done

all_files=( "${compose_files[@]}" )
if ((${#extra[@]} > 0)); then
  all_files+=( "${extra[@]}" )
fi
exec docker compose "${all_files[@]}" "$@"
