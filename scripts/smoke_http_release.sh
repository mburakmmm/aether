#!/usr/bin/env bash
# HTTP smoke via `noxc build --release` (LLVM M:N pool, macOS/arm64).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34569}"
BIN="/tmp/aether-release-smoke"
cd "$ROOT"

rm -f "$BIN" /tmp/aether-smoke-rel.log
AETHER_ENV=production \
AETHER_PORT="$PORT" \
AETHER_WORKERS="${AETHER_WORKERS:-2}" \
AETHER_OPENAPI=0 \
AETHER_LOG_REQUESTS=0 \
AETHER_CORS_ORIGINS= \
AETHER_METRICS_ROUTES=0 \
noxc build --release -o "$BIN" benchmarks/aether/main.nox

AETHER_ENV=production \
AETHER_PORT="$PORT" \
AETHER_WORKERS="${AETHER_WORKERS:-2}" \
AETHER_OPENAPI=0 \
AETHER_LOG_REQUESTS=0 \
AETHER_CORS_ORIGINS= \
AETHER_METRICS_ROUTES=0 \
"$BIN" >/tmp/aether-smoke-rel.log 2>&1 &
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
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "release smoke failed; server exited early:" >&2
    cat /tmp/aether-smoke-rel.log >&2 || true
    exit 1
  fi
  sleep 0.25
  i=$((i + 1))
done
if [[ "$ok" != "1" ]]; then
  echo "release smoke failed; server log:" >&2
  cat /tmp/aether-smoke-rel.log >&2 || true
  exit 1
fi

j=0
while [[ $j -lt 20 ]]; do
  curl -fsS "http://127.0.0.1:${PORT}/ping" | grep -q pong
  j=$((j + 1))
done

echo_body="$(curl -fsS -X POST "http://127.0.0.1:${PORT}/echo" \
  -H 'Content-Type: application/json' \
  -d '{"msg":"rel"}')"
echo "$echo_body" | grep -q rel

echo "smoke http --release ok"
