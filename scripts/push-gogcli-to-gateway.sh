#!/usr/bin/env bash
# Copy host-staged gogcli (OPENCLAW_GOGCLI_CONFIG_DIR, default .openclaw-gog-config) into the
# running openclaw-gateway using **tar over docker exec**.
#
# With docker-compose.gog.yml, /home/node/.config/gogcli is a **named volume** (Linux ext4 in the
# VM). Streaming bytes from the host avoids Docker Desktop bind-mount stat/open failures from macOS.
#
# Run after: make sync-gog-config (or it is invoked automatically from sync / restart targets).
# Requires: gateway container running.
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

DST_REL="${OPENCLAW_GOGCLI_CONFIG_DIR:-./.openclaw-gog-config}"
if [[ "$DST_REL" == /* ]]; then
  DST="$DST_REL"
else
  DST="$ROOT_DIR/$DST_REL"
fi

command -v docker >/dev/null 2>&1 || {
  echo "push-gogcli-to-gateway: docker not found" >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  echo "push-gogcli-to-gateway: docker daemon not reachable" >&2
  exit 1
}

[[ -f "$DST/credentials.json" ]] || {
  echo "push-gogcli-to-gateway: no $DST/credentials.json — skipping (configure gog on host, then make sync-gog-config)." >&2
  exit 0
}

gateway_cid() {
  local cid=""
  if [[ -f "$ROOT_DIR/docker-compose.dev.yml" ]]; then
    cid="$(cd "$ROOT_DIR" && ./scripts/docker-compose.sh -f docker-compose.dev.yml ps -q openclaw-gateway 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "$cid" ]]; then
    cid="$(cd "$ROOT_DIR" && ./scripts/docker-compose.sh ps -q openclaw-gateway 2>/dev/null | head -n1 || true)"
  fi
  printf '%s' "$cid"
}

CID="$(gateway_cid)"
if [[ -z "$CID" ]]; then
  echo "push-gogcli-to-gateway: no running openclaw-gateway (skipped). Start the stack, then re-run:" >&2
  echo "  ./scripts/push-gogcli-to-gateway.sh" >&2
  exit 0
fi

# After `docker compose up --force-recreate`, the container is "running" before Node answers /healthz.
# Streaming tar while the gateway is still restarting closes stdin → host tar reports "Write error".
wait_for_gateway_healthz() {
  local i max=90
  echo "push-gogcli-to-gateway: waiting for gateway /healthz (up to ${max}s)…" >&2
  for ((i = 1; i <= max; i++)); do
    if docker exec "$CID" sh -c \
      'command -v node >/dev/null 2>&1 && node -e "fetch(\"http://127.0.0.1:18789/healthz\").then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"' \
      2>/dev/null; then
      echo "push-gogcli-to-gateway: gateway ready after ${i}s" >&2
      return 0
    fi
    sleep 1
  done
  echo "push-gogcli-to-gateway: error: /healthz not OK after ${max}s — gateway is crash-looping or misconfigured." >&2
  echo "  If you recently merged timeouts: jq 'del(.agents.defaults.timeoutSeconds, .agents.defaults.llm)' .openclaw-config/openclaw.json (via tmp+mv), then make restart-dev. See docs/TROUBLESHOOTING.md" >&2
  echo "  Logs: ./scripts/docker-compose.sh logs --tail=120 openclaw-gateway" >&2
  return 1
}

if ! wait_for_gateway_healthz; then
  exit 1
fi

echo "push-gogcli-to-gateway: streaming $DST -> gateway $CID:/home/node/.config/gogcli (tar + chown)"

docker exec -u 0 "$CID" sh -c 'mkdir -p /home/node/.config/gogcli && rm -rf /home/node/.config/gogcli/* /home/node/.config/gogcli/.[!.]* 2>/dev/null || true'

stream_tar_from_dst() {
  # macOS: omit AppleDouble (._*) and Finder junk; they confuse GNU tar (xattr pax / utime errors).
  # COPYFILE_DISABLE avoids resource-fork sidecars when archiving from APFS/HFS+.
  if [[ -r "$DST/credentials.json" ]]; then
    (cd "$DST" && COPYFILE_DISABLE=1 tar cf - --exclude='._*' --exclude='.DS_Store' .)
    return 0
  fi
  if sudo -n sh -c "cd \"$DST\" && COPYFILE_DISABLE=1 tar cf - --exclude='._*' --exclude='.DS_Store' ." 2>/dev/null; then
    return 0
  fi
  if [[ -t 0 ]] && command -v sudo >/dev/null 2>&1; then
    echo "push-gogcli-to-gateway: sudo password required to read staging files (mode 600, UID 1000)." >&2
    sudo sh -c "cd \"$DST\" && COPYFILE_DISABLE=1 tar cf - --exclude='._*' --exclude='.DS_Store' ."
    return 0
  fi
  echo "push-gogcli-to-gateway: cannot read $DST (need sudo or chown staging to your user)." >&2
  return 1
}

if ! stream_tar_from_dst | docker exec -i -u 0 "$CID" sh -c '
  set -e
  cd /home/node/.config/gogcli
  tar xf - --no-same-owner --warning=no-unknown-keyword || tar xf - --no-same-owner
  chown -R 1000:1000 .
  find . -type d -exec chmod 755 {} +
  find . -type f -exec chmod 600 {} +
'; then
  echo "push-gogcli-to-gateway: error: tar stream failed (broken pipe usually means gateway restarted mid-push). Re-run: ./scripts/push-gogcli-to-gateway.sh" >&2
  exit 1
fi

echo "push-gogcli-to-gateway: done. Verify: ./scripts/docker-compose.sh exec -T openclaw-gateway ls -la /home/node/.config/gogcli/credentials.json"
