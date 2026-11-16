#!/usr/bin/env bash
# SIGTERM does not write the drain file. finalize_serve writes it when serve returns.
# request_shutdown stops accept. An in-flight /slow must not keep the process past the drain timeout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34723}"
LIFE_BASE="${AETHER_LIFECYCLE_DIR:-/tmp/aether-life-drain-signal}"
cd "$ROOT"

OUT="${TMPDIR:-/tmp}/aether-drain-signal"
rm -rf "$OUT" "$LIFE_BASE"
mkdir -p "$OUT" "$LIFE_BASE"
LOG="$OUT/server.log"
LIFE_DIR="$LIFE_BASE/$PORT"

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
    kill -9 "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  if [[ -n "${SLOW:-}" ]]; then
    kill -9 "$SLOW" 2>/dev/null || true
    wait "$SLOW" 2>/dev/null || true
  fi
  kill_port
}
trap cleanup EXIT
kill_port

start_server() {
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
  export AETHER_LIFECYCLE_DIR="$LIFE_BASE"
  export AETHER_DRAIN_TIMEOUT_MS="${AETHER_DRAIN_TIMEOUT_MS:-400}"
  noxc run benchmarks/drain_probe/main.nox >"$LOG" 2>&1 &
  PID=$!
  local ok=0
  for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1; then
      ok=1
      break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "drain probe exited" >&2
      cat "$LOG" >&2 || true
      exit 1
    fi
    sleep 0.5
  done
  if [[ "$ok" != "1" ]]; then
    echo "drain probe did not become ready" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
}

start_server
rm -f "$LIFE_DIR/stopping"
# noxc is the parent. The signal handler lives in the listen process.
LISTEN="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN | head -1 || true)"
if [[ -z "$LISTEN" ]]; then
  echo "no listen process" >&2
  exit 1
fi
kill -TERM "$LISTEN"
waited=0
for _ in $(seq 1 50); do
  if ! kill -0 "$PID" 2>/dev/null; then
    waited=1
    break
  fi
  sleep 0.1
done
if [[ "$waited" != "1" ]]; then
  echo "SIGTERM did not return from serve" >&2
  exit 1
fi
wait "$PID" 2>/dev/null || true
PID=""
if [[ ! -f "$LIFE_DIR/stopping" ]]; then
  echo "finalize_serve did not write the drain file after SIGTERM" >&2
  exit 1
fi
echo "sigterm wrote $LIFE_DIR/stopping"

rm -rf "$LIFE_BASE"
mkdir -p "$LIFE_BASE"
: >"$LOG"
start_server
curl -sS --max-time 8 "http://127.0.0.1:${PORT}/slow" >/dev/null 2>&1 &
SLOW=$!
sleep 0.2
# shutdown() inside /die stops accept before the response is written.
# The process must still return within the drain timeout, not the 3s handler.
curl -sS -o /dev/null -w '%{http_code}' --max-time 2 -X POST "http://127.0.0.1:${PORT}/die" >/dev/null 2>&1 || true
left=0
for _ in $(seq 1 20); do
  if ! kill -0 "$PID" 2>/dev/null; then
    left=1
    break
  fi
  sleep 0.1
done
if [[ "$left" != "1" ]]; then
  echo "request_shutdown did not return within the drain timeout" >&2
  exit 1
fi
wait "$PID" 2>/dev/null || true
PID=""
echo "smoke drain signal ok"
