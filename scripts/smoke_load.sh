#!/usr/bin/env bash
# Record requests/sec, non-2xx, read errors, and p99. No pass threshold on RPS.
# workers=1 also runs a bare Nox ping. Read errors only fail when Aether has
# them and the bare server does not. workers>1 also samples boot ids.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=aether_env.sh
source "$ROOT/scripts/aether_env.sh"

if ! command -v wrk >/dev/null 2>&1; then
  echo "wrk is not installed" >&2
  exit 2
fi

PORT="${AETHER_PORT:-34730}"
BARE_PORT="${AETHER_BARE_PORT:-34731}"
PROBE_PORT="${AETHER_PROBE_PORT:-34732}"
WORKERS="${AETHER_WORKERS:-1}"
LOAD_SECONDS="${AETHER_LOAD_SECONDS:-30}"
MODE="${AETHER_PROBE_MODE:-llvm}" # llvm | qbe | release
OUT="$ROOT/benchmarks/results"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
TAG="w${WORKERS}-${MODE}-${STAMP}"

export AETHER_ENV=production
export AETHER_WORKERS="$WORKERS"
export NOX_POOL_WORKERS="$WORKERS"
export AETHER_HTTP2=0
export AETHER_OPENAPI=0
export AETHER_LOG_REQUESTS=0
export AETHER_REQUEST_ID=0
export AETHER_METRICS=0
export AETHER_METRICS_ROUTES=0
export AETHER_CORS_ORIGINS=
export AETHER_REQUEST_HEADERS=0

kill_port() {
  local port="$1"
  local pids
  pids="$(lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

PID=""
cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  kill_port "$PORT"
  kill_port "$BARE_PORT"
  kill_port "$PROBE_PORT"
}
trap cleanup EXIT

wait_http() {
  local url="$1"
  local i=0
  while [[ $i -lt 80 ]]; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if [[ -n "${PID:-}" ]] && ! kill -0 "$PID" 2>/dev/null; then
      return 1
    fi
    sleep 0.25
    i=$((i + 1))
  done
  return 1
}

start_aether() {
  local port="$1"
  local log="$2"
  export AETHER_PORT="$port"
  if [[ "$MODE" == "release" ]]; then
    local bin="$OUT/aether-load-${TAG}"
    if [[ ! -x "$bin" ]]; then
      noxc build --release -o "$bin" benchmarks/aether/main.nox
    fi
    "$bin" >"$log" 2>&1 &
  elif [[ "$MODE" == "qbe" ]]; then
    noxc run --backend qbe benchmarks/aether/main.nox >"$log" 2>&1 &
  else
    noxc run benchmarks/aether/main.nox >"$log" 2>&1 &
  fi
  PID=$!
}

field() {
  local file="$1"
  local key="$2"
  local value="0"
  case "$key" in
    p99)
      value="$(awk '/^[[:space:]]+99%/ { print $2; exit }' "$file")"
      ;;
    rps)
      value="$(awk '/^Requests\/sec:/ { print $2; exit }' "$file")"
      ;;
    non2xx)
      value="$(awk '/Non-2xx or 3xx responses:/ { print $NF; exit }' "$file")"
      ;;
    read)
      value="$(awk '/Socket errors:/ { for (i = 1; i <= NF; i++) if ($i == "read") { print $(i + 1); exit } }' "$file" | tr -d ',')"
      ;;
  esac
  if [[ -z "$value" ]]; then
    if [[ "$key" == "p99" || "$key" == "rps" ]]; then
      value="-"
    else
      value="0"
    fi
  fi
  printf '%s' "$value"
}

SUMMARY="$OUT/load-${TAG}.txt"
{
  echo "workers=$WORKERS mode=$MODE seconds=$LOAD_SECONDS noxc=$(noxc version 2>/dev/null || echo unknown)"
  echo "http=1.1"
} >"$SUMMARY"

kill_port "$PORT"
LOG="$OUT/aether-${TAG}.log"
start_aether "$PORT" "$LOG"
if ! wait_http "http://127.0.0.1:${PORT}/ping"; then
  echo "aether load server failed" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

PING="$OUT/aether-ping-${TAG}.txt"
ECHO="$OUT/aether-echo-${TAG}.txt"
wrk -t4 -c40 -d"${LOAD_SECONDS}s" --latency "http://127.0.0.1:${PORT}/ping" | tee "$PING"
LUA="$OUT/echo.lua"
cat >"$LUA" <<'EOF'
wrk.method = "POST"
wrk.body   = '{"msg":"hello"}'
wrk.headers["Content-Type"] = "application/json"
EOF
wrk -t4 -c40 -d"${LOAD_SECONDS}s" --latency -s "$LUA" "http://127.0.0.1:${PORT}/echo" | tee "$ECHO"

A_READ="$(field "$PING" read)"
A_NON="$(field "$PING" non2xx)"
E_NON="$(field "$ECHO" non2xx)"
{
  echo "aether_ping rps=$(field "$PING" rps) non_2xx=$A_NON read_errors=$A_READ p99=$(field "$PING" p99)"
  echo "aether_echo rps=$(field "$ECHO" rps) non_2xx=$E_NON read_errors=$(field "$ECHO" read) p99=$(field "$ECHO" p99)"
} | tee -a "$SUMMARY"

if [[ "$A_NON" != "0" || "$E_NON" != "0" ]]; then
  echo "non-2xx responses during load" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=""

BARE_READ="0"
if [[ "$WORKERS" == "1" ]]; then
  kill_port "$BARE_PORT"
  BARE_LOG="$OUT/bare-${TAG}.log"
  AETHER_PORT="$BARE_PORT" noxc run benchmarks/bare_ping/main.nox >"$BARE_LOG" 2>&1 &
  PID=$!
  if ! wait_http "http://127.0.0.1:${BARE_PORT}/"; then
    echo "bare ping failed" >&2
    cat "$BARE_LOG" >&2 || true
    exit 1
  fi
  BARE="$OUT/bare-ping-${TAG}.txt"
  wrk -t4 -c40 -d"${LOAD_SECONDS}s" --latency "http://127.0.0.1:${BARE_PORT}/" | tee "$BARE"
  BARE_READ="$(field "$BARE" read)"
  echo "bare_ping rps=$(field "$BARE" rps) non_2xx=$(field "$BARE" non2xx) read_errors=$BARE_READ p99=$(field "$BARE" p99)" | tee -a "$SUMMARY"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
  if [[ "$A_READ" != "0" && "$BARE_READ" == "0" ]]; then
    echo "read errors are on Aether only" >&2
    exit 1
  fi
  if [[ "$A_READ" != "0" && "$BARE_READ" != "0" ]]; then
    echo "read errors also on bare Nox; recorded, not an Aether failure" | tee -a "$SUMMARY"
  fi
fi

if [[ "$WORKERS" != "1" ]]; then
  mkdir -p /tmp/aether-boot-markers
  kill_port "$PROBE_PORT"
  PLOG="$OUT/probe-${TAG}.log"
  export AETHER_PORT="$PROBE_PORT"
  export AETHER_REQUEST_HEADERS=1
  if [[ "$MODE" == "release" ]]; then
    pbin="$OUT/probe-load-${TAG}"
    noxc build --release -o "$pbin" benchmarks/worker_probe/main.nox
    "$pbin" >"$PLOG" 2>&1 &
  elif [[ "$MODE" == "qbe" ]]; then
    noxc run --backend qbe benchmarks/worker_probe/main.nox >"$PLOG" 2>&1 &
  else
    noxc run benchmarks/worker_probe/main.nox >"$PLOG" 2>&1 &
  fi
  PID=$!
  if ! wait_http "http://127.0.0.1:${PROBE_PORT}/ping"; then
    echo "worker probe failed" >&2
    cat "$PLOG" >&2 || true
    exit 1
  fi
  IDS="$OUT/boot-ids-${TAG}.txt"
  : >"$IDS"
  sample_ids() {
    local n=0
    while [[ $n -lt 200 ]]; do
      curl -fsS "http://127.0.0.1:${PROBE_PORT}/__worker" >>"$IDS" || true
      echo >>"$IDS"
      n=$((n + 1))
    done
  }
  sample_ids &
  SAMPLER=$!
  PWRK="$OUT/probe-ping-${TAG}.txt"
  wrk -t4 -c40 -d"${LOAD_SECONDS}s" --latency "http://127.0.0.1:${PROBE_PORT}/ping" | tee "$PWRK"
  wait "$SAMPLER" || true
  unique="$(grep -o 'boot_id":"[^"]*' "$IDS" | sort -u | wc -l | tr -d ' ')"
  pnon="$(field "$PWRK" non2xx)"
  echo "probe_ping rps=$(field "$PWRK" rps) non_2xx=$pnon read_errors=$(field "$PWRK" read) p99=$(field "$PWRK" p99) boot_ids=$unique" | tee -a "$SUMMARY"
  if [[ "$pnon" != "0" ]]; then
    echo "non-2xx responses on the worker probe" >&2
    exit 1
  fi
fi

echo "smoke load summary: $SUMMARY"
echo "smoke load ok"
