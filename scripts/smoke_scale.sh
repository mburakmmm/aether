#!/usr/bin/env bash
# Multicore scale record. No RPS threshold. boot_ids=1 is recorded, not a failure.
# Ping is the small JSON path. Echo is a parsed JSON body. CPU is the listen
# process percent sampled once a second during wrk; the line keeps the maximum.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${HOME}/.nox-lang/bin:${PATH:-}"
unset NOX_POOL_WORKERS || true

if ! command -v wrk >/dev/null 2>&1; then
  echo "wrk is not installed" >&2
  exit 2
fi

SECONDS_LOAD="${AETHER_SCALE_SECONDS:-20}"
OUT="$ROOT/benchmarks/results"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
SUMMARY="$OUT/scale-${STAMP}.txt"
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
{
  echo "seconds=$SECONDS_LOAD ncpu=$NCPU noxc=$(noxc version 2>/dev/null || echo unknown)"
  echo "wrk=-t4 -c40 http=1.1"
} | tee "$SUMMARY"

kill_port() {
  local port="$1"
  local pids
  pids="$(lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

field() {
  local file="$1"
  local key="$2"
  local value="0"
  case "$key" in
    p99) value="$(awk '/^[[:space:]]+99%/ { print $2; exit }' "$file")" ;;
    rps) value="$(awk '/^Requests\/sec:/ { print $2; exit }' "$file")" ;;
    non2xx) value="$(awk '/Non-2xx or 3xx responses:/ { print $NF; exit }' "$file")" ;;
    read) value="$(awk '/Socket errors:/ { for (i = 1; i <= NF; i++) if ($i == "read") { print $(i + 1); exit } }' "$file" | tr -d ',')" ;;
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

PID=""
PORT=34740
cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  kill_port "$PORT"
}
trap cleanup EXIT

wait_http() {
  local i=0
  while [[ $i -lt 80 ]]; do
    if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1; then
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

max_cpu() {
  local listen seconds="$1"
  listen="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  local max=0
  local n=0
  local sample
  while [[ $n -lt $seconds ]]; do
    if [[ -n "$listen" ]]; then
      sample="$(ps -p "$listen" -o pcpu= 2>/dev/null | awk '{ printf "%d", $1 }' || echo 0)"
      if [[ -z "$sample" ]]; then
        sample=0
      fi
      if [[ "$sample" -gt "$max" ]]; then
        max="$sample"
      fi
    fi
    sleep 1
    n=$((n + 1))
  done
  printf '%s' "$max"
}

export AETHER_ENV=production
export AETHER_HTTP2=0
export AETHER_OPENAPI=0
export AETHER_LOG_REQUESTS=0
export AETHER_REQUEST_ID=0
export AETHER_METRICS=0
export AETHER_METRICS_ROUTES=0
export AETHER_CORS_ORIGINS=
export AETHER_WS=0
export AETHER_HTTP3=0

LUA="$OUT/scale-echo.lua"
cat >"$LUA" <<'EOF'
wrk.method = "POST"
wrk.body   = '{"msg":"hello"}'
wrk.headers["Content-Type"] = "application/json"
EOF

for WORKERS in 1 2 4 8; do
  export AETHER_WORKERS="$WORKERS"
  export NOX_POOL_WORKERS="$WORKERS"
  export AETHER_PORT="$PORT"
  export AETHER_REQUEST_HEADERS=0
  kill_port "$PORT"
  LOG="$OUT/scale-aether-w${WORKERS}-${STAMP}.log"
  noxc run benchmarks/aether/main.nox >"$LOG" 2>&1 &
  PID=$!
  if ! wait_http; then
    echo "aether workers=$WORKERS failed" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  PING="$OUT/scale-ping-w${WORKERS}-${STAMP}.txt"
  ECHO="$OUT/scale-echo-w${WORKERS}-${STAMP}.txt"
  max_cpu "$SECONDS_LOAD" >"$OUT/scale-cpu-ping-w${WORKERS}-${STAMP}.txt" &
  CPID=$!
  wrk -t4 -c40 -d"${SECONDS_LOAD}s" --latency "http://127.0.0.1:${PORT}/ping" | tee "$PING"
  wait "$CPID" || true
  PCPU="$(cat "$OUT/scale-cpu-ping-w${WORKERS}-${STAMP}.txt")"
  max_cpu "$SECONDS_LOAD" >"$OUT/scale-cpu-echo-w${WORKERS}-${STAMP}.txt" &
  CPID=$!
  wrk -t4 -c40 -d"${SECONDS_LOAD}s" --latency -s "$LUA" "http://127.0.0.1:${PORT}/echo" | tee "$ECHO"
  wait "$CPID" || true
  ECPU="$(cat "$OUT/scale-cpu-echo-w${WORKERS}-${STAMP}.txt")"
  PN="$(field "$PING" non2xx)"
  EN="$(field "$ECHO" non2xx)"
  echo "w=$WORKERS ping rps=$(field "$PING" rps) p99=$(field "$PING" p99) non_2xx=$PN read=$(field "$PING" read) cpu_max=${PCPU} echo rps=$(field "$ECHO" rps) p99=$(field "$ECHO" p99) non_2xx=$EN read=$(field "$ECHO" read) cpu_max=${ECPU}" | tee -a "$SUMMARY"
  if [[ "$PN" != "0" || "$EN" != "0" ]]; then
    echo "non-2xx during scale" >&2
    exit 1
  fi
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""

  mkdir -p /tmp/aether-boot-markers
  export AETHER_REQUEST_HEADERS=1
  kill_port "$PORT"
  PLOG="$OUT/scale-probe-w${WORKERS}-${STAMP}.log"
  noxc run benchmarks/worker_probe/main.nox >"$PLOG" 2>&1 &
  PID=$!
  if ! wait_http; then
    echo "probe workers=$WORKERS failed" >&2
    cat "$PLOG" >&2 || true
    exit 1
  fi
  IDS="$OUT/scale-ids-w${WORKERS}-${STAMP}.txt"
  : >"$IDS"
  (
    n=0
    while [[ $n -lt $((SECONDS_LOAD * 10)) ]]; do
      curl -fsS "http://127.0.0.1:${PORT}/__worker" >>"$IDS" || true
      echo >>"$IDS"
      n=$((n + 1))
    done
  ) &
  SID=$!
  PWRK="$OUT/scale-probe-ping-w${WORKERS}-${STAMP}.txt"
  wrk -t4 -c40 -d"${SECONDS_LOAD}s" --latency "http://127.0.0.1:${PORT}/ping" | tee "$PWRK"
  wait "$SID" || true
  unique="$(grep -o 'boot_id":"[^"]*' "$IDS" | sort -u | wc -l | tr -d ' ')"
  echo "w=$WORKERS probe rps=$(field "$PWRK" rps) p99=$(field "$PWRK" p99) non_2xx=$(field "$PWRK" non2xx) read=$(field "$PWRK" read) boot_ids=$unique" | tee -a "$SUMMARY"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
  export AETHER_REQUEST_HEADERS=0
done

echo "SCALE_DONE $SUMMARY"
