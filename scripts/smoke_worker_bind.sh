#!/usr/bin/env bash
# Prove AppBind / Application boot locality under workers>1.
#
# Evidence channels:
#   1) HTTP GET /__worker → boot_id (only workers that served)
#   2) /tmp/aether-boot-markers/*.boot → every build() (validation boot + serving workers)
#
# boot_for_serve validates once then clears idle parent AppBind when workers>1;
# sibling workers still boot via dispatch_ensure on first request.
#
# Interpretation:
#   markers > http_unique  → validation boot and/or extra slots beyond those hit
#   http_unique >= 2       → multiple workers served (strong worker-local proof)
#   markers == 1 && workers>1 → only one slot ever ran build() (accept affinity)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34670}"
WORKERS="${AETHER_WORKERS:-4}"
MODE="${AETHER_PROBE_MODE:-qbe}" # qbe | release
REQUESTS="${AETHER_PROBE_REQUESTS:-400}"
PARALLEL="${AETHER_PROBE_PARALLEL:-40}"
MARKERS="${AETHER_BOOT_MARKERS:-/tmp/aether-boot-markers}"
cd "$ROOT"
# shellcheck source=aether_env.sh
source "$ROOT/scripts/aether_env.sh"
AETHER_WORKERS="$WORKERS"
aether_export_pool_workers

OUT_DIR="${TMPDIR:-/tmp}/aether-worker-probe"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/server.log"
IDS_FILE="$OUT_DIR/ids.txt"
BIN="$OUT_DIR/worker-probe"

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
rm -rf "$MARKERS"
mkdir -p "$MARKERS"

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
export AETHER_REQUEST_HEADERS=0

if [[ "$MODE" == "release" ]]; then
  echo "building --release probe (workers=$WORKERS)..."
  noxc build --release -o "$BIN" benchmarks/worker_probe/main.nox
  "$BIN" >"$LOG" 2>&1 &
  PID=$!
else
  echo "starting QBE probe (workers=$WORKERS)..."
  noxc run benchmarks/worker_probe/main.nox >"$LOG" 2>&1 &
  PID=$!
fi

ok=0
i=0
while [[ $i -lt 120 ]]; do
  if curl -fsS "http://127.0.0.1:${PORT}/ping" 2>/dev/null | grep -q pong; then
    ok=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "worker probe server exited early:" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  sleep 0.25
  i=$((i + 1))
done
if [[ "$ok" != "1" ]]; then
  echo "worker probe failed to become ready:" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

: >"$IDS_FILE"
echo "probing /__worker requests=$REQUESTS parallel=$PARALLEL ..."
done_n=0
while [[ $done_n -lt $REQUESTS ]]; do
  batch=$PARALLEL
  left=$((REQUESTS - done_n))
  if [[ $batch -gt $left ]]; then
    batch=$left
  fi
  pids=()
  b=0
  while [[ $b -lt $batch ]]; do
    (
      body="$(curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/__worker" 2>/dev/null || true)"
      echo "$body" | sed -n 's/.*"boot_id":"\([^"]*\)".*/\1/p'
    ) >>"$IDS_FILE" &
    pids+=($!)
    b=$((b + 1))
  done
  for p in "${pids[@]}"; do
    wait "$p" || true
  done
  done_n=$((done_n + batch))
done

grep -E '^[0-9a-fA-F-]{8,}$' "$IDS_FILE" >"$OUT_DIR/ids.clean" || true
TOTAL=$(wc -l <"$OUT_DIR/ids.clean" | tr -d ' ')
UNIQUE=$(sort -u "$OUT_DIR/ids.clean" | wc -l | tr -d ' ')
MARK_N=$(find "$MARKERS" -name '*.boot' 2>/dev/null | wc -l | tr -d ' ')
LOG_N=0
LOG_U=0
if [[ -f "$MARKERS/builds.log" ]]; then
  LOG_N=$(wc -l <"$MARKERS/builds.log" | tr -d ' ')
  LOG_U=$(sort -u "$MARKERS/builds.log" | grep -c . || true)
fi

echo "mode=$MODE workers=$WORKERS"
echo "http_responses=$TOTAL http_unique_boot_ids=$UNIQUE"
echo "build_marker_files=$MARK_N builds_log_lines=$LOG_N builds_log_unique=$LOG_U"
sort -u "$OUT_DIR/ids.clean" | sed 's/^/  http_boot_id=/'
if [[ -f "$MARKERS/builds.log" ]]; then
  sort -u "$MARKERS/builds.log" | sed 's/^/  build_id=/'
fi

if [[ "$TOTAL" -lt 10 ]]; then
  echo "too few successful responses ($TOTAL); server log:" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

if [[ "$WORKERS" -le 1 ]]; then
  if [[ "$UNIQUE" -ne 1 ]]; then
    echo "FAIL: workers=1 expected http_unique=1 got $UNIQUE" >&2
    exit 1
  fi
  echo "worker probe ok: single-worker"
  exit 0
fi

# Soft assertions for investigation (exit 0 with RESULT lines).
if [[ "$MARK_N" -ge 2 ]]; then
  echo "RESULT: build() ran $MARK_N times → AppBind/globals NOT a single process-wide boot"
fi
if [[ "$UNIQUE" -ge 2 ]]; then
  echo "RESULT: http_unique=$UNIQUE → multiple workers served (worker-local Application observed)"
elif [[ "$MARK_N" -ge 2 && "$UNIQUE" -eq 1 ]]; then
  echo "RESULT: multi-boot but single serving worker (accept affinity / idle sibling slots)"
elif [[ "$MARK_N" -eq 1 && "$UNIQUE" -eq 1 ]]; then
  echo "RESULT: only one build+serve slot observed under workers=$WORKERS (affinity or shared path)"
fi

# CI hard mode: require multi-boot or multi-serve evidence.
if [[ "${AETHER_PROBE_REQUIRE_MULTI:-0}" == "1" ]]; then
  if [[ "$UNIQUE" -lt 2 && "$MARK_N" -lt 2 ]]; then
    echo "FAIL: REQUIRE_MULTI needs http_unique>=2 or build_markers>=2" >&2
    exit 1
  fi
fi
echo "worker probe ok"
