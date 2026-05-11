#!/usr/bin/env bash
# Lightweight patterns that should never appear in tracked source (CI only).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scan_rg() {
  if rg --hidden -n "AIza[0-9A-Za-z_-]{10,}" --glob '!.git/*' --glob '!.env.example' --glob '!.env.generated' "$ROOT_DIR"; then
    echo "ci-secret-scan: possible Google API key material" >&2
    return 1
  fi
  if rg --hidden -n "sk-[A-Za-z0-9]{20,}" --glob '!.git/*' --glob '!.env.example' --glob '!.env.generated' "$ROOT_DIR"; then
    echo "ci-secret-scan: possible OpenAI-style API key" >&2
    return 1
  fi
  if rg --hidden -n "BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY" --glob '!.git/*' --glob '!.env.generated' "$ROOT_DIR"; then
    echo "ci-secret-scan: PEM private key block" >&2
    return 1
  fi
  return 0
}

scan_git_grep() {
  # Tracked files only; excludes .env.example via pathspec
  if git grep -nE "AIza[0-9A-Za-z_-]{10,}" -- . ":(exclude).env.example" >/dev/null 2>&1; then
    echo "ci-secret-scan: possible Google API key material" >&2
    return 1
  fi
  if git grep -nE "sk-[A-Za-z0-9]{20,}" -- . ":(exclude).env.example" >/dev/null 2>&1; then
    echo "ci-secret-scan: possible OpenAI-style API key" >&2
    return 1
  fi
  if git grep -nE "BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY" -- . >/dev/null 2>&1; then
    echo "ci-secret-scan: PEM private key block" >&2
    return 1
  fi
  return 0
}

if command -v rg >/dev/null 2>&1; then
  scan_rg
else
  scan_git_grep
fi

echo "ci-secret-scan: OK"
