#!/usr/bin/env bash
# Download a Linux ELF goplaces binary from steipete/goplaces releases into .openclaw-host-bin/goplaces.
# Docker containers are Linux: a macOS Homebrew goplaces (Mach-O) cannot run inside them.
#
# Usage (from repo root):
#   ./scripts/install-goplaces-linux-for-docker.sh
#   GOPLACES_LINUX_ARCH=arm64 ./scripts/install-goplaces-linux-for-docker.sh
#   GOPLACES_RELEASE_TAG=v0.4.0 ./scripts/install-goplaces-linux-for-docker.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${ROOT_DIR}/.openclaw-host-bin"
mkdir -p "$OUT_DIR"

ARCH="${GOPLACES_LINUX_ARCH:-amd64}"
case "$ARCH" in
  amd64 | arm64) ;;
  *)
    echo "install-goplaces-linux-for-docker: GOPLACES_LINUX_ARCH must be amd64 or arm64 (got $ARCH)" >&2
    exit 1
    ;;
esac

if ! command -v curl >/dev/null 2>&1; then
  echo "install-goplaces-linux-for-docker: install curl" >&2
  exit 1
fi

if [[ -n "${GOPLACES_RELEASE_TAG:-}" ]]; then
  TAG="${GOPLACES_RELEASE_TAG}"
else
  if ! command -v jq >/dev/null 2>&1; then
    echo "install-goplaces-linux-for-docker: install jq or set GOPLACES_RELEASE_TAG=vX.Y.Z" >&2
    exit 1
  fi
  TAG="$(curl -fsSL https://api.github.com/repos/steipete/goplaces/releases/latest | jq -r .tag_name)"
fi
VER="${TAG#v}"
ASSET="goplaces_${VER}_linux_${ARCH}.tar.gz"
URL="https://github.com/steipete/goplaces/releases/download/${TAG}/${ASSET}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/goplacesdl.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "install-goplaces-linux-for-docker: fetching $URL"
curl -fsSL -o "$TMP/$ASSET" "$URL"
tar -xzf "$TMP/$ASSET" -C "$TMP" goplaces
install -m 0755 "$TMP/goplaces" "${OUT_DIR}/goplaces"

echo "install-goplaces-linux-for-docker: installed Linux goplaces -> ${OUT_DIR}/goplaces"
if command -v file >/dev/null 2>&1; then
  file "${OUT_DIR}/goplaces"
fi
echo "Next: set GOOGLE_PLACES_API_KEY in .env, then make restart-dev"
