#!/usr/bin/env bash
# Print the path to the deploy instances manifest (local overrides example).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="${DEPLOY_INSTANCES_FILE:-$ROOT_DIR/deploy/instances.json}"
EXAMPLE="$ROOT_DIR/deploy/instances.example.json"

if [[ -f "$LOCAL" ]]; then
  echo "$LOCAL"
elif [[ -f "$EXAMPLE" ]]; then
  echo "$EXAMPLE"
else
  echo "resolve-deploy-manifest: missing $LOCAL and $EXAMPLE" >&2
  exit 1
fi
