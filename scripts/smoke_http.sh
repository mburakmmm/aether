#!/usr/bin/env bash
# HTTP smoke: boot Aether bench app and hit /ping (single worker).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34567}"
cd "$ROOT"

rm -f /tmp/aether-smoke.log
AETHER_ENV=production \
AETHER_PORT="$PORT" \
AETHER_WORKERS=1 \
AETHER_OPENAPI=0 \
AETHER_LOG_REQUESTS=0 \
AETHER_CORS_ORIGINS= \
AETHER_METRICS_ROUTES=0 \
noxc run benchmarks/aether/main.nox >/tmp/aether-smoke.log 2>&1 &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap cleanup EXIT

ok=0
i=0
while [[ $i -lt 80 ]]; do
  if curl -fsS "http://127.0.0.1:${PORT}/ping" 2>/dev/null | grep -q pong; then
    ok=1
    break
  fi
  # Fail fast if the server process died during boot.
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "smoke failed; server exited early:" >&2
    cat /tmp/aether-smoke.log >&2 || true
    exit 1
  fi
  sleep 0.25
  i=$((i + 1))
done
if [[ "$ok" != "1" ]]; then
  echo "smoke failed; server log:" >&2
  cat /tmp/aether-smoke.log >&2 || true
  exit 1
fi

echo "smoke http ok"
