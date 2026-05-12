#!/usr/bin/env bash
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

PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

# After `docker compose up -d`, the port may accept TCP before Node returns HTTP (curl 52 "Empty reply").
MAX_WAIT="${HEALTHCHECK_MAX_WAIT_SECONDS:-180}"
INTERVAL="${HEALTHCHECK_INTERVAL_SECONDS:-3}"
start_ts=$SECONDS
deadline=$((start_ts + MAX_WAIT))

# Plain curl can stall on Expect: 100-continue with some HTTP stacks; match a reliable probe:
#   curl --noproxy '*' --http1.1 -H 'Expect:' ...
probe() {
  curl --noproxy '*' --http1.1 -H 'Expect:' --max-time 30 -fsS \
    "http://127.0.0.1:${PORT}/healthz" >/dev/null
}

attempt=0
until probe; do
  attempt=$((attempt + 1))
  if (( SECONDS >= deadline )); then
    echo "healthcheck: timed out after ${MAX_WAIT}s (${attempt} failed attempts) — http://127.0.0.1:${PORT}/healthz" >&2
    echo "healthcheck: tip: set HEALTHCHECK_MAX_WAIT_SECONDS in .env on slow VMs; check gateway logs." >&2
    exit 1
  fi
  sleep "$INTERVAL"
done

elapsed=$((SECONDS - start_ts))
if (( attempt == 0 )); then
  echo "healthcheck: /healthz OK on port $PORT"
else
  echo "healthcheck: /healthz OK on port $PORT (${attempt} retries, ${elapsed}s)"
fi
