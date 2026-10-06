#!/usr/bin/env bash
# Prove coordinated graceful drain under workers>1.
#
# 1) Start probe with AETHER_SHUTDOWN_ROUTE=1
# 2) Warm workers via /__worker
# 3) POST /__aether/shutdown
# 4) Subsequent /ping and /health must be 503
# 5) Worker registry under lifecycle dir drains to 0 (or near-0 after traffic)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34680}"
WORKERS="${AETHER_WORKERS:-4}"
MODE="${AETHER_PROBE_MODE:-qbe}" # qbe | release
LIFE_BASE="${AETHER_LIFECYCLE_DIR:-/tmp/aether-life-smoke}"
MARKERS="${AETHER_BOOT_MARKERS:-/tmp/aether-boot-markers-shutdown}"
cd "$ROOT"
# shellcheck source=aether_env.sh
source "$ROOT/scripts/aether_env.sh"
AETHER_WORKERS="$WORKERS"
aether_export_pool_workers

OUT_DIR="${TMPDIR:-/tmp}/aether-shutdown-smoke"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/server.log"
BIN="$OUT_DIR/shutdown-probe"
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
  kill_port
}
trap cleanup EXIT

kill_port
rm -rf "$MARKERS" "$LIFE_DIR"
mkdir -p "$MARKERS" "$LIFE_BASE"

export AETHER_ENV=production
export AETHER_PORT="$PORT"
export AETHER_WORKERS="$WORKERS"
export NOX_POOL_WORKERS="$NOX_POOL_WORKERS"
export AETHER_OPENAPI=0
export AETHER_LOG_REQUESTS=0
export AETHER_CORS_ORIGINS=
export AETHER_METRICS=0
export AETHER_METRICS_ROUTES=0
export AETHER_REQUEST_ID=0
export AETHER_REQUEST_HEADERS=1
export AETHER_SHUTDOWN_ROUTE=1
export AETHER_LIFECYCLE_DIR="$LIFE_BASE"
export AETHER_BOOT_MARKERS="$MARKERS"

if [[ "$MODE" == "release" ]]; then
  echo "building --release shutdown probe (workers=$WORKERS)..."
  noxc build --release -o "$BIN" benchmarks/worker_probe/main.nox
  "$BIN" >"$LOG" 2>&1 &
  PID=$!
else
  echo "starting QBE shutdown probe (workers=$WORKERS)..."
  noxc run benchmarks/worker_probe/main.nox >"$LOG" 2>&1 &
  PID=$!
fi

ok=0
for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 0.1
done
if [[ "$ok" != "1" ]]; then
  echo "server failed to become ready" >&2
  tail -n 80 "$LOG" >&2 || true
  exit 1
fi

# Warm as many workers as accept affinity allows.
for _ in $(seq 1 120); do
  curl -fsS "http://127.0.0.1:${PORT}/__worker" >/dev/null || true
done

before_workers=0
if [[ -d "$LIFE_DIR/workers" ]]; then
  before_workers="$(find "$LIFE_DIR/workers" -type f 2>/dev/null | wc -l | tr -d ' ')"
fi
echo "workers registered before drain: $before_workers"

code_shutdown="$(curl -sS -o /tmp/aether-shutdown-body.json -w '%{http_code}' \
  -X POST "http://127.0.0.1:${PORT}/__aether/shutdown")"
if [[ "$code_shutdown" != "200" ]]; then
  echo "expected shutdown POST 200, got $code_shutdown" >&2
  cat /tmp/aether-shutdown-body.json >&2 || true
  exit 1
fi

if [[ ! -f "$LIFE_DIR/stopping" ]]; then
  echo "missing stopping flag at $LIFE_DIR/stopping" >&2
  exit 1
fi

# Other workers cache "not stopping" for AETHER_STOP_POLL_MS (default 200).
# Wait out that window before requiring 503.
sleep 0.5

# Drive drain: each live worker should 503 once and unregister.
fail_503=0
for _ in $(seq 1 200); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/ping" || true)"
  if [[ "$code" != "503" ]]; then
    fail_503=1
    echo "expected /ping 503 after begin_shutdown, got $code" >&2
    break
  fi
done
if [[ "$fail_503" != "0" ]]; then
  exit 1
fi

code_health="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health" || true)"
if [[ "$code_health" != "503" ]]; then
  echo "expected /health 503 while stopping, got $code_health" >&2
  exit 1
fi

# Poll registry drain.
drained=0
for _ in $(seq 1 80); do
  n=0
  if [[ -d "$LIFE_DIR/workers" ]]; then
    n="$(find "$LIFE_DIR/workers" -type f 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if [[ "$n" == "0" ]]; then
    drained=1
    break
  fi
  # Extra traffic helps drain workers that have not accepted since the flag.
  curl -sS -o /dev/null "http://127.0.0.1:${PORT}/ping" || true
  sleep 0.05
done

after_workers=0
if [[ -d "$LIFE_DIR/workers" ]]; then
  after_workers="$(find "$LIFE_DIR/workers" -type f 2>/dev/null | wc -l | tr -d ' ')"
fi
echo "workers registered after drain: $after_workers (drained=$drained)"

if [[ "$drained" != "1" ]]; then
  echo "worker registry did not drain to 0 (left=$after_workers)" >&2
  ls -la "$LIFE_DIR/workers" >&2 || true
  exit 1
fi

echo "smoke_shutdown ok (mode=$MODE workers=$WORKERS)"
