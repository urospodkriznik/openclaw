#!/usr/bin/env bash
# Base packages and host hardening notes for Ubuntu 24.04 (run with sudo on a fresh VM).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/setup-server.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  jq \
  make \
  rsync \
  ufw \
  gnupg \
  software-properties-common

echo "==> UFW: allowing SSH (adjust if you use a non-standard port)"
ufw allow OpenSSH || true
ufw --force enable || true

echo "==> Done. Next:"
echo "    sudo ./scripts/setup-swap.sh"
echo "    sudo ./scripts/install-docker.sh"
echo "Do not expose gateway port 18789 publicly without TLS and auth hardening — see docs/SECURITY.md"
