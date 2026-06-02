#!/usr/bin/env bash
# Copy operator-managed workspace instructions from config/operator/ into the agent workspace.
# Does not touch memory/, SOUL.md, USER.md, IDENTITY.md, or skills/.
#
# Usage (repo root):
#   ./scripts/sync-operator-workspace.sh
#   ./scripts/sync-operator-workspace.sh <instance-id>   # optional per-instance overrides
#
# Overrides: config/operator/instances/<id>/TOOLS.md or AGENTS.md if present.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
INSTANCE_ID="${1:-${OPENCLAW_INSTANCE_ID:-}}"

OPERATOR_DIR="${ROOT_DIR}/config/operator"
MARKER_BEGIN='<!-- OPENCLAW_OPERATOR:BEGIN -->'
MARKER_END='<!-- OPENCLAW_OPERATOR:END -->'

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-./workspace}"
if [[ "$WORKSPACE_DIR" != /* ]]; then
  WORKSPACE_DIR="$ROOT_DIR/$WORKSPACE_DIR"
fi

resolve_operator_file() {
  local base="$1"
  local path="${OPERATOR_DIR}/${base}"
  if [[ -n "$INSTANCE_ID" && -f "${OPERATOR_DIR}/instances/${INSTANCE_ID}/${base}" ]]; then
    path="${OPERATOR_DIR}/instances/${INSTANCE_ID}/${base}"
  fi
  if [[ ! -f "$path" ]]; then
    echo "sync-operator-workspace: missing $path" >&2
    return 1
  fi
  printf '%s' "$path"
}

sync_tools_md() {
  local src
  src="$(resolve_operator_file "TOOLS.md")"
  mkdir -p "$WORKSPACE_DIR"
  cp -f "$src" "${WORKSPACE_DIR}/TOOLS.md"
  echo "sync-operator-workspace: wrote ${WORKSPACE_DIR}/TOOLS.md"
}

extract_operator_block() {
  local src="$1"
  awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
    $0 == b { p=1; print; next }
  p { print; if ($0 == e) exit }
  ' "$src"
}

merge_agents_md() {
  local src dst block
  src="$(resolve_operator_file "AGENTS.md")"
  dst="${WORKSPACE_DIR}/AGENTS.md"
  mkdir -p "$WORKSPACE_DIR"
  block="$(extract_operator_block "$src")"
  if [[ -z "$block" ]]; then
    echo "sync-operator-workspace: no operator block in $src" >&2
    exit 1
  fi

  if [[ ! -f "$dst" ]]; then
    cp -f "$src" "$dst"
    echo "sync-operator-workspace: created ${dst}"
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "sync-operator-workspace: python3 required to merge AGENTS.md" >&2
    exit 1
  fi

  python3 - "$dst" "$block" <<'PY'
import sys
from pathlib import Path

dst = Path(sys.argv[1])
block = sys.argv[2]
begin = "<!-- OPENCLAW_OPERATOR:BEGIN -->"
end = "<!-- OPENCLAW_OPERATOR:END -->"

text = dst.read_text(encoding="utf-8") if dst.exists() else ""
if begin in text and end in text:
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    new = pre.rstrip() + "\n\n" + block.strip() + "\n" + post.lstrip("\n")
else:
    new = (text.rstrip() + "\n\n" + block.strip() + "\n").lstrip("\n")
dst.write_text(new, encoding="utf-8")
PY
  echo "sync-operator-workspace: merged operator block into ${dst}"
}

main() {
  if [[ ! -d "$OPERATOR_DIR" ]]; then
    echo "sync-operator-workspace: missing $OPERATOR_DIR" >&2
    exit 1
  fi
  sync_tools_md
  merge_agents_md
  if [[ -f "${OPERATOR_DIR}/HEARTBEAT.md" ]]; then
    cp -f "${OPERATOR_DIR}/HEARTBEAT.md" "${WORKSPACE_DIR}/HEARTBEAT.md"
    echo "sync-operator-workspace: wrote ${WORKSPACE_DIR}/HEARTBEAT.md"
  fi
  if [[ -n "$INSTANCE_ID" ]]; then
    echo "sync-operator-workspace: instance overrides id=$INSTANCE_ID"
  fi
}

main
