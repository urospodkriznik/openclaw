#!/usr/bin/env bash
# Quick checks when the gateway logs "Missing config" but host openclaw.json looks fine.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-./.openclaw-config}"
CFG="${CONFIG_DIR}/openclaw.json"
fail=0

echo "diagnose-openclaw-config: CONFIG_DIR=$CONFIG_DIR"

if [[ ! -f "$CFG" ]]; then
  echo "ERROR: missing $CFG" >&2
  exit 1
fi

if ! jq -e . "$CFG" >/dev/null 2>&1; then
  echo "ERROR: $CFG is not valid JSON" >&2
  exit 1
fi
echo "OK: valid JSON"

mode="$(jq -r '.gateway.mode // empty' "$CFG")"
if [[ "$mode" == "local" ]]; then
  echo "OK: gateway.mode=local"
else
  echo "WARN: gateway.mode is '${mode:-<unset>}' (expected local)" >&2
  fail=1
fi

if jq -e '.models.providers' "$CFG" >/dev/null 2>&1; then
  echo "WARN: openclaw.json has models.providers — a minimal provider object can crash some images; see docs/TROUBLESHOOTING.md" >&2
fi

dir_stat="$(stat -c '%a %u %g' "$CONFIG_DIR" 2>/dev/null || stat -f '%OLp %u %g' "$CONFIG_DIR")"
echo ".openclaw-config dir permissions/owner: $dir_stat"
dir_perm="${dir_stat%% *}"
if [[ "$dir_perm" == "700" ]] && [[ "$(id -u)" -ne 1000 ]]; then
  echo "ERROR: .openclaw-config is mode 700 — UID 1000 cannot traverse; use: chmod 755 $CONFIG_DIR" >&2
  fail=1
fi

stat_out="$(stat -c '%a %u %g' "$CFG" 2>/dev/null || stat -f '%OLp %u %g' "$CFG")"
echo "openclaw.json permissions/owner: $stat_out"

perm="${stat_out%% *}"
owner_uid="${stat_out#* }"
owner_uid="${owner_uid%% *}"

# Container gateway runs as UID 1000. File must be readable by 1000 unless deploy user is 1000.
if [[ "$(id -u)" -ne 1000 ]] && [[ "$owner_uid" != "1000" ]]; then
  if [[ "$perm" == "600" ]] || [[ "$perm" == "400" ]]; then
    echo "ERROR: mode $perm — UID 1000 in the container cannot read this file (common after: cp openclaw.json.bak openclaw.json)" >&2
    echo "Fix: chmod 644 $CFG   OR   sudo ./scripts/reown-openclaw-mounts.sh --container" >&2
    fail=1
  fi
fi

for sub in logs credentials; do
  p="${CONFIG_DIR}/${sub}"
  if [[ -e "$p" ]] && [[ ! -w "$p" ]] && [[ "$(stat -c '%u' "$p" 2>/dev/null || stat -f '%u' "$p")" != "1000" ]]; then
    echo "WARN: $p not writable by UID 1000 — gateway may log EACCES; run: sudo ./scripts/reown-openclaw-mounts.sh --container" >&2
    fail=1
  fi
done

if command -v docker >/dev/null 2>&1; then
  if ./scripts/docker-compose.sh ps openclaw-gateway 2>/dev/null | grep -qE 'Up|running'; then
    echo "--- container view ---"
    ./scripts/docker-compose.sh exec -T openclaw-gateway \
      sh -c 'test -r /home/node/.openclaw/openclaw.json && jq -r ".gateway.mode" /home/node/.openclaw/openclaw.json || echo "NOT_READABLE"' \
      2>/dev/null || echo "(exec failed — gateway may be restarting)"
  else
    echo "gateway container not running — start after fixing permissions, then re-run this script"
  fi
fi

exit "$fail"
