#!/usr/bin/env bash
# Deploy every instance listed in deploy/instances.json (on the VM or over SSH).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$(./scripts/resolve-deploy-manifest.sh)"
DEPLOY_USER_HOME="${DEPLOY_USER_HOME:-$HOME}"

if ! command -v jq >/dev/null 2>&1; then
  echo "deploy-all: install jq" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "deploy-all: missing $MANIFEST" >&2
  exit 1
fi

mapfile -t PATHS < <(jq -r '.instances[].path' "$MANIFEST")
mapfile -t IDS < <(jq -r '.instances[].id' "$MANIFEST")

fail=0
for i in "${!PATHS[@]}"; do
  id="${IDS[$i]}"
  rel="${PATHS[$i]}"
  target="${DEPLOY_USER_HOME}/${rel}"
  echo ""
  echo "========== deploy-all: $id ($target) =========="
  if [[ ! -d "$target/.git" ]]; then
    echo "deploy-all: skip $id — no git repo at $target (clone first)" >&2
    fail=1
    continue
  fi
  (
    cd "$target"
    git fetch origin
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      git checkout main
      git pull --ff-only origin main
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then
      git checkout master
      git pull --ff-only origin master
    else
      echo "deploy-all: no origin/main or origin/master in $target" >&2
      exit 1
    fi
    touch .env
    grep -v '^USE_GSM_SECRETS=' .env > .env.tmp || true
    mv .env.tmp .env
    echo 'USE_GSM_SECRETS=true' >> .env
    ./scripts/remote-deploy.sh "$id"
  ) || fail=1
done

if ((fail != 0)); then
  echo "deploy-all: one or more instances failed" >&2
  exit 1
fi

echo "deploy-all: all instances OK"
