#!/usr/bin/env bash
# Download a Linux ELF gog binary from openclaw/gogcli releases into .openclaw-host-bin/gog.
# Docker containers are Linux: a macOS Homebrew gog (Mach-O) cannot run inside them.
#
# Usage (from repo root):
#   ./scripts/install-gog-linux-for-docker.sh
#   GOG_LINUX_ARCH=arm64 ./scripts/install-gog-linux-for-docker.sh   # if your image is linux/arm64
#   GOGCLI_RELEASE_TAG=v0.16.0 ./scripts/install-gog-linux-for-docker.sh   # pin a release
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${ROOT_DIR}/.openclaw-host-bin"
mkdir -p "$OUT_DIR"

ARCH="${GOG_LINUX_ARCH:-amd64}"
case "$ARCH" in
  amd64 | arm64) ;;
  *)
    echo "install-gog-linux-for-docker: GOG_LINUX_ARCH must be amd64 or arm64 (got $ARCH)" >&2
    exit 1
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "install-gog-linux-for-docker: install curl" >&2
  exit 1
fi

if [[ -n "${GOGCLI_RELEASE_TAG:-}" ]]; then
  TAG="${GOGCLI_RELEASE_TAG}"
else
  if ! command -v jq >/dev/null 2>&1; then
    echo "install-gog-linux-for-docker: install jq or set GOGCLI_RELEASE_TAG=vX.Y.Z" >&2
    exit 1
  fi
  TAG="$(curl -fsSL https://api.github.com/repos/openclaw/gogcli/releases/latest | jq -r .tag_name)"
fi
VER="${TAG#v}"
ASSET="gogcli_${VER}_linux_${ARCH}.tar.gz"
URL="https://github.com/openclaw/gogcli/releases/download/${TAG}/${ASSET}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gogdl.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "install-gog-linux-for-docker: fetching $URL"
curl -fsSL -o "$TMP/$ASSET" "$URL"
tar -xzf "$TMP/$ASSET" -C "$TMP" gog
install -m 0755 "$TMP/gog" "${OUT_DIR}/gog"

echo "install-gog-linux-for-docker: installed Linux gog -> ${OUT_DIR}/gog"
if command -v file >/dev/null 2>&1; then
  file "${OUT_DIR}/gog"
fi
echo "Next: ./scripts/docker-compose.sh … config   # should still include docker-compose.gog.yml"
echo "      make restart-dev"
