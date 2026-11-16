#!/usr/bin/env bash
# Two hundred requests on one pooled connection. The first stores aether.jwt.
# None of the later responses may contain it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34721}"
cd "$ROOT"

OUT="${TMPDIR:-/tmp}/aether-keepalive"
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
export AETHER_REQUEST_HEADERS=1

noxc run benchmarks/keepalive_probe/main.nox >"$LOG" 2>&1 &
PID=$!

ok=0
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${PORT}/who" >/dev/null 2>&1; then
    ok=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "keepalive server exited" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
    sleep 0.5
done
if [[ "$ok" != "1" ]]; then
  echo "keepalive server did not become ready" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

noxc run benchmarks/keepalive_probe/client.nox
echo "smoke keepalive ok"
