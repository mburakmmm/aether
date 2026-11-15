#!/usr/bin/env bash
# workers=1 WebSocket: join, drop, join again, oversized frame, then a denied token.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34722}"
cd "$ROOT"

OUT="${TMPDIR:-/tmp}/aether-ws"
rm -rf "$OUT"
mkdir -p "$OUT"
LOG="$OUT/server.log"

kill_port() {
  local pids
  pids="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  kill_port
}
trap cleanup EXIT
kill_port

start_server() {
  local mode="$1"
  noxc run benchmarks/ws_probe/main.nox >"$LOG" 2>&1 &
  PID=$!
  local ok=0
  for _ in $(seq 1 80); do
    if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1; then
      ok=1
      break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "ws server exited mode=$mode" >&2
      cat "$LOG" >&2 || true
      exit 1
    fi
    sleep 0.1
  done
  if [[ "$ok" != "1" ]]; then
    echo "ws server did not become ready mode=$mode" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
}

stop_server() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    PID=""
  fi
  kill_port
}

export AETHER_ENV=production
export AETHER_PORT="$PORT"
export AETHER_WORKERS=1
export NOX_POOL_WORKERS=1
export AETHER_HTTP2=0
export AETHER_OPENAPI=0
export AETHER_LOG_REQUESTS=0
export AETHER_REQUEST_ID=0
export AETHER_METRICS=0
export AETHER_CORS_ORIGINS=
export AETHER_WS=0
unset AETHER_WS_MODE || true

start_server allow
AETHER_WS_MODE= noxc run benchmarks/ws_probe/client.nox
stop_server

export AETHER_WS_MODE=deny
start_server deny
noxc run benchmarks/ws_probe/client.nox
stop_server

echo "smoke ws ok"
