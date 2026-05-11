#!/usr/bin/env bash
# Create 4G swap file (recommended for e2-micro + OpenClaw container).
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/setup-swap.sh"
  exit 1
fi

SWAPFILE="${SWAPFILE:-/swapfile}"
SIZE_GB="${SWAP_SIZE_GB:-4}"

if swapon --show | grep -qF "$SWAPFILE"; then
  echo "Swap already active on $SWAPFILE"
  exit 0
fi

if [[ -f "$SWAPFILE" ]]; then
  echo "Using existing $SWAPFILE"
else
  fallocate -l "${SIZE_GB}G" "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SIZE_GB * 1024))
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
fi

swapon "$SWAPFILE"

if ! grep -qF "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap sw 0 0" >>/etc/fstab
fi

echo "Swap enabled:"
swapon --show
